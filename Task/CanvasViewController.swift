import UIKit

final class CanvasViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    weak var navigator: TaskSplitNavigating?
    private var sidebarToggleButton: UIBarButtonItem?
    /// «+ ⌄» рядом с иконкой сайдбара, пока сайдбар закрыт
    private var addMenuButton: UIBarButtonItem?
    private var closeButton: UIBarButtonItem?
    private var showsSidebarToggle = false
    private var board = BoardSample.initial
    private var boardTitleItem: UIBarButtonItem?
    private let boardTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.textAlignment = .left
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let boardSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    /// Заголовок доски — обычный view поверх навбара, а не элемент навбара: так при открытии
    /// сайдбара он просто сдвигается и не попадает в системный блюр перестройки кнопок.
    /// В навбаре на его месте стоит пустой элемент `boardTitleItem` той же ширины
    private let boardTitleStack = UIStackView()
    private var boardTitleLeading: NSLayoutConstraint?
    private var boardTitleIsInBar = false
    /// iPhone: заголовок доски обычным элементом навбара, рядом с кнопкой «Назад»
    var prefersTitleInBar = false
    /// Позиция заголовка за кнопками «✕»/сайдбара. Внутри анимации навбар ещё не расставил
    /// новые кнопки, поэтому берём последнее стабильное значение (начальное — замер на iPad)
    private var titleXBehindToggle: CGFloat = 198
    /// Пока колонка анимируется, заголовок двигает только transitionCoordinator
    private var isSidebarTransitioning = false
    private var searchButton: UIBarButtonItem?
    private var viewModeCheckButton: UIBarButtonItem?
    private var viewModeBoardButton: UIBarButtonItem?
    private var viewModeListButton: UIBarButtonItem?
    private var viewModeMoreButton: UIBarButtonItem?
    private var addColumnButton: UIBarButtonItem?
    /// iPhone: панель вида внизу слева и «Добавить колонку» внизу справа
    private let phoneToolbar = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let phoneNewTaskButton = UIButton(type: .system)
    private weak var phoneFiltersButton: UIView?

    private let boardScroll = UIScrollView()
    private let columnsStack = UIStackView()
    private var columnViews: [BoardColumnView] = []

    private static let columnSpacing: CGFloat = 24
    /// На iPad колонка чуть уже, чтобы четвёртая выглядывала из-за края и было видно, что доска листается
    private static var columnWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 280 : 320
    }
    private static let boardTitleWidth: CGFloat = 220

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Нативный фон: сайдбар iPadOS — полупрозрачное стекло, и фон доски просвечивает сквозь него
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.applyNotesAccentAppearance(showsInlineTitle: true)
        view.tintColor = .notesAccent
        navigationItem.style = .editor
        configureSidebarToggle()
        configureBoardTitle()
        configureViewModeButtons()
        configureSearchButton()
        configureBoard()
        configurePhoneToolbar()
        display(board: board)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachBoardTitleIfNeeded()
        if !isSidebarTransitioning {
            alignBoardTitleWithFirstColumn()
        }
    }

    /// Ставит заголовок доски: при открытом сайдбаре — по левому краю первой колонки,
    /// при закрытом — сразу за кнопками «✕» и сайдбара (на место пустого элемента навбара)
    private func alignBoardTitleWithFirstColumn() {
        // Заголовок внутри навбара (iPhone) — навбар сам ставит его на место
        guard !boardTitleIsInBar else { return }
        guard let leading = boardTitleLeading,
              let container = boardTitleStack.superview,
              let placeholder = boardTitleItem?.customView
        else { return }
        let x: CGFloat
        if showsSidebarToggle {
            if !isSidebarTransitioning, placeholder.window != nil {
                let measured = placeholder.convert(CGPoint.zero, to: container).x
                if measured > 0 { titleXBehindToggle = measured }
            }
            x = titleXBehindToggle
        } else {
            let columnX = view.safeAreaInsets.left + boardScroll.contentInset.left
            x = view.convert(CGPoint(x: columnX, y: 0), to: container).x
        }
        if abs(leading.constant - x) > 0.5 {
            leading.constant = x
            container.layoutIfNeeded()
        }
    }

    private func attachBoardTitleIfNeeded() {
        guard boardTitleStack.superview == nil,
              let container = navigationController?.view,
              let bar = navigationController?.navigationBar,
              let placeholder = boardTitleItem?.customView,
              bar.window != nil
        else { return }
        // На iPhone сайдбар и доска сворачиваются в один стек навигации, и навбар оказывается
        // вне `container` — тогда заголовок живёт прямо в своём элементе навбара
        guard bar.isDescendant(of: container), !prefersTitleInBar else {
            boardTitleIsInBar = true
            placeholder.addSubview(boardTitleStack)
            let leading = boardTitleStack.leadingAnchor.constraint(equalTo: placeholder.leadingAnchor)
            boardTitleLeading = leading
            NSLayoutConstraint.activate([
                leading,
                boardTitleStack.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor),
                boardTitleStack.trailingAnchor.constraint(lessThanOrEqualTo: placeholder.trailingAnchor)
            ])
            return
        }
        container.addSubview(boardTitleStack)
        let leading = boardTitleStack.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        boardTitleLeading = leading
        NSLayoutConstraint.activate([
            leading,
            boardTitleStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            boardTitleStack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.boardTitleWidth)
        ])
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.alignBoardTitleWithFirstColumn()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.applyNotesAccentAppearance(showsInlineTitle: true)
        navigationController?.navigationBar.tintColor = .notesAccent
        view.tintColor = .notesAccent
        navigationItem.style = .editor
        applyCollapsedSidebarButtons()
        navigationController?.navigationBar.applyNotesAccentToBarSymbols()
        applyPhoneTheme()
    }

    func display(board: Board) {
        // Открытая задача относится к прежней доске — закрываем инспектор
        if let detail = taskDetail, board.task(withID: detail.task.id) == nil {
            navigator?.hideTaskDetail()
            taskDetail = nil
        }
        self.board = board
        refreshBoardTitle()
        rebuildColumns()
        applyPhoneTheme()
    }

    // MARK: - Цвет доски как тема экрана (iPhone)

    /// Кнопки нижней панели — перекрашиваются вместе с доской
    private var phoneToolbarButtons: [(button: UIButton, symbol: String?)] = []

    /// На iPhone весь экран доски в её цвете: «‹», поиск, нижняя панель и «+»
    private func applyPhoneTheme() {
        guard prefersTitleInBar, isViewLoaded else { return }
        let color = board.iconBottom
        view.tintColor = color

        func tinted(_ image: UIImage?) -> UIImage? {
            image?.withTintColor(color, renderingMode: .alwaysOriginal)
        }
        for (button, symbol) in phoneToolbarButtons {
            let image = symbol.map { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(weight: UIImage.barSymbolWeight)) }
                ?? UIImage.addColumnGlyph()
            button.setImage(tinted(image ?? nil), for: .normal)
            button.tintColor = color
        }
        phoneNewTaskButton.configuration?.baseBackgroundColor = color
        phoneNewTaskButton.tintColor = color

        searchButton?.image = tinted(UIImage.notesBarGlyph("magnifyingglass"))
        // Стрелка «Назад» — своя для этого экрана, в цвете доски
        let appearance = navigationController?.navigationBar.standardAppearance.copy() ?? UINavigationBarAppearance()
        if let chevron = tinted(UIImage(
            systemName: "chevron.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: UIImage.barSymbolPointSize, weight: UIImage.barSymbolWeight)
        )) {
            appearance.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
    }

    private func configureBoardTitle() {
        boardTitleStack.addArrangedSubview(boardTitleLabel)
        boardTitleStack.addArrangedSubview(boardSubtitleLabel)
        boardTitleStack.axis = .vertical
        boardTitleStack.alignment = .leading
        boardTitleStack.spacing = 0
        boardTitleStack.translatesAutoresizingMaskIntoConstraints = false

        // Пустое место в навбаре под заголовок: держит раскладку кнопок и даёт позицию за «✕»/сайдбаром
        let placeholder = UIView(frame: CGRect(x: 0, y: 0, width: Self.boardTitleWidth, height: 44))
        placeholder.isUserInteractionEnabled = false
        let item = UIBarButtonItem(customView: placeholder)
        item.hidesSharedBackground = true
        boardTitleItem = item
    }

    private func configureSearchButton() {
        searchButton = makeCapsuleButton(
            symbol: "magnifyingglass",
            action: nil,
            accessibilityLabel: "Поиск"
        )
    }

    private func configureViewModeButtons() {
        viewModeCheckButton = makeViewModeButton(
            symbol: "checkmark.circle",
            accessibilityLabel: "Завершённые"
        )
        viewModeBoardButton = makeViewModeButton(
            symbol: "rectangle.split.3x1",
            accessibilityLabel: "Доска"
        )
        viewModeListButton = makeViewModeButton(
            symbol: "line.3.horizontal.decrease",
            accessibilityLabel: "Фильтры",
            action: #selector(showFilters)
        )
        viewModeMoreButton = makeViewModeButton(
            symbol: "ellipsis",
            accessibilityLabel: "Ещё"
        )
        let addColumn = UIBarButtonItem(
            image: .addColumnGlyph(),
            style: .plain,
            target: self,
            action: #selector(addColumnTapped)
        )
        addColumn.tintColor = .notesAccent
        addColumn.accessibilityLabel = "Новая колонка"
        addColumnButton = addColumn
    }

    // MARK: - Новая колонка

    @objc private func addColumnTapped() {
        let alert = UIAlertController(title: "Новая колонка", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Название"
            field.autocapitalizationType = .sentences
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        let create = UIAlertAction(title: "Создать", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.addColumn(title: text.isEmpty ? "Новая колонка" : text)
        }
        alert.addAction(create)
        alert.preferredAction = create
        present(alert, animated: true)
    }

    /// Новая колонка берёт цвет доски
    private func addColumn(title: String) {
        applyBoardChange(board.appendingColumn(BoardColumn(title: title, tasks: [])))
        view.layoutIfNeeded()
        let maxOffsetX = boardScroll.contentSize.width - boardScroll.bounds.width + boardScroll.adjustedContentInset.right
        if maxOffsetX > boardScroll.contentOffset.x {
            boardScroll.setContentOffset(CGPoint(x: maxOffsetX, y: boardScroll.contentOffset.y), animated: true)
        }
    }

    // MARK: - Нижняя панель на iPhone

    /// Новая задача — в первую колонку доски
    @objc private func phoneNewTaskTapped() {
        guard !board.columns.isEmpty else { return }
        presentNewTask(from: phoneNewTaskButton, columnIndex: 0)
    }

    private func configurePhoneToolbar() {
        guard prefersTitleInBar else { return }
        let size: CGFloat = 48
        phoneToolbar.cornerConfiguration = .capsule()
        phoneToolbar.translatesAutoresizingMaskIntoConstraints = false
        // nil в символе — иконка «Добавить колонку» (рисуется отдельно)
        let items: [(String?, String, Selector?)] = [
            ("checkmark.circle", "Завершённые", nil),
            ("rectangle.split.3x1", "Доска", nil),
            ("line.3.horizontal.decrease", "Фильтры", #selector(showFilters)),
            (nil, "Новая колонка", #selector(addColumnTapped)),
            ("ellipsis", "Ещё", nil)
        ]
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (symbol, label, action) in items {
            let button = UIButton(type: .system)
            button.setImage(symbol.map { .notesBarSymbol($0) } ?? UIImage.addColumnGlyph(), for: .normal)
            button.tintColor = .notesAccent
            button.accessibilityLabel = label
            if let action { button.addTarget(self, action: action, for: .touchUpInside) }
            if action == #selector(showFilters) { phoneFiltersButton = button }
            phoneToolbarButtons.append((button, symbol))
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            stack.addArrangedSubview(button)
        }
        phoneToolbar.contentView.addSubview(stack)
        view.addSubview(phoneToolbar)

        // Справа — зелёная круглая «+» новой задачи, как на главном экране
        var config = UIButton.Configuration.prominentGlass()
        config.image = UIImage(systemName: "plus",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: UIImage.appSymbolWeight))
        config.baseBackgroundColor = .notesAccent
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        phoneNewTaskButton.configuration = config
        phoneNewTaskButton.tintColor = .notesAccent
        phoneNewTaskButton.accessibilityLabel = "Новая задача"
        phoneNewTaskButton.addTarget(self, action: #selector(phoneNewTaskTapped), for: .touchUpInside)
        phoneNewTaskButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneNewTaskButton)

        // Как нижние кнопки «Почты» и «Напоминаний» и круглая «+» на главном: 28 pt от краёв экрана
        let inset: CGFloat = 28
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: phoneToolbar.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: phoneToolbar.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: phoneToolbar.contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: phoneToolbar.contentView.trailingAnchor, constant: -4),
            phoneToolbar.heightAnchor.constraint(equalToConstant: size),
            phoneToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            phoneToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset),

            phoneNewTaskButton.widthAnchor.constraint(equalToConstant: size),
            phoneNewTaskButton.heightAnchor.constraint(equalToConstant: size),
            phoneNewTaskButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            phoneNewTaskButton.centerYAnchor.constraint(equalTo: phoneToolbar.centerYAnchor)
        ])
        boardScroll.contentInset.bottom = size + 40
    }

    private func refreshBoardTitle() {
        boardTitleLabel.text = board.title
        boardSubtitleLabel.text = Self.taskCountLabel(board.columns.reduce(0) { $0 + $1.tasks.count })
        title = nil
        navigationItem.subtitle = nil
        applyCollapsedSidebarButtons()
    }

    private static func taskCountLabel(_ count: Int) -> String {
        let n10 = count % 10
        let n100 = count % 100
        if n10 == 1, n100 != 11 { return "\(count) задача" }
        if (2...4).contains(n10), !(12...14).contains(n100) { return "\(count) задачи" }
        return "\(count) задач"
    }

    private func configureBoard() {
        boardScroll.translatesAutoresizingMaskIntoConstraints = false
        boardScroll.alwaysBounceHorizontal = true
        boardScroll.alwaysBounceVertical = true
        boardScroll.showsHorizontalScrollIndicator = false
        boardScroll.contentInsetAdjustmentBehavior = .always
        // Отступы слева и справа равны расстоянию между колонками
        boardScroll.contentInset = UIEdgeInsets(
            top: 24,
            left: Self.columnSpacing,
            bottom: 80,
            right: Self.columnSpacing
        )
        view.addSubview(boardScroll)

        columnsStack.axis = .horizontal
        columnsStack.alignment = .top
        columnsStack.spacing = Self.columnSpacing
        columnsStack.translatesAutoresizingMaskIntoConstraints = false
        boardScroll.addSubview(columnsStack)

        NSLayoutConstraint.activate([
            boardScroll.topAnchor.constraint(equalTo: view.topAnchor),
            boardScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            boardScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            boardScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            columnsStack.topAnchor.constraint(equalTo: boardScroll.contentLayoutGuide.topAnchor),
            columnsStack.leadingAnchor.constraint(equalTo: boardScroll.contentLayoutGuide.leadingAnchor),
            columnsStack.trailingAnchor.constraint(equalTo: boardScroll.contentLayoutGuide.trailingAnchor),
            columnsStack.bottomAnchor.constraint(equalTo: boardScroll.contentLayoutGuide.bottomAnchor)
        ])
    }

    private func rebuildColumns() {
        columnsStack.arrangedSubviews.forEach { view in
            columnsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        columnViews = board.columns.map { column in
            let view = BoardColumnView()
            view.apply(column: column, color: board.color(of: column))
            view.onChangeColor = { [weak self, weak view] color in
                guard let self, let view,
                      let index = self.columnsStack.arrangedSubviews.firstIndex(of: view),
                      self.board.columns.indices.contains(index)
                else { return }
                let column = self.board.columns[index].with(customColor: color)
                self.board = self.board.replacingColumn(at: index, with: column)
                self.navigator?.didUpdateBoard(self.board)
                view.apply(column: column, color: self.board.color(of: column))
            }
            // Индекс колонки берём в момент нажатия: колонки можно переставлять без пересборки
            view.onNewTask = { [weak self, weak view] button in
                guard let self, let view,
                      let index = self.columnsStack.arrangedSubviews.firstIndex(of: view)
                else { return }
                self.presentNewTask(from: button, columnIndex: index)
            }
            view.onCardTap = { [weak self] card in
                self?.openTaskDetail(for: card)
            }
            view.onCardReorderGesture = { [weak self, weak view] gesture, card in
                guard let self, let view else { return }
                self.handleCardReorder(gesture, card: card, column: view)
            }
            view.onReorderGesture = { [weak self, weak view] gesture in
                guard let self, let view else { return }
                self.handleColumnReorder(gesture, column: view)
            }
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
            columnsStack.addArrangedSubview(view)
            return view
        }
    }

    private func presentNewTask(from button: UIButton, columnIndex: Int) {
        let sheet = NewTaskViewController()
        sheet.modalPresentationStyle = .popover
        sheet.preferredContentSize = CGSize(width: 380, height: 290)
        sheet.onCreate = { [weak self] title, isFlagged in
            self?.insertTask(title: title, isFlagged: isFlagged, columnIndex: columnIndex)
        }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = button
            popover.sourceRect = button.bounds
            popover.permittedArrowDirections = .any
            popover.delegate = self
        }
        present(sheet, animated: true)
    }

    private func insertTask(title: String, isFlagged: Bool, columnIndex: Int) {
        let task = BoardTask(title: title, subtitle: "", tags: [], isFlagged: isFlagged)
        applyBoardChange(board.insertingTask(task, inColumn: columnIndex))
    }

    // MARK: - Карточка задачи (инспектор справа)

    private weak var taskDetail: TaskDetailViewController?

    private func openTaskDetail(for card: TaskCardView) {
        guard columnDrag == nil, cardDrag == nil,
              let id = card.taskID,
              let found = board.task(withID: id)
        else { return }
        let detail = TaskDetailViewController(
            task: found.task,
            board: board,
            boards: navigator?.allBoards() ?? [board],
            // На iPhone карточка задачи в цвете доски
            accent: prefersTitleInBar ? board.iconBottom : .notesAccent
        )
        detail.onChange = { [weak self] task in self?.updateTaskFromDetail(task) }
        detail.onMoveToColumn = { [weak self] column in
            guard let self else { return }
            self.applyBoardChange(self.board.movingTask(id: id, toColumn: column))
        }
        detail.onMoveToBoard = { [weak self] boardID in self?.moveTask(id: id, toBoardID: boardID) }
        detail.onDuplicate = { [weak self] in self?.duplicateTask(id: id) }
        detail.onDelete = { [weak self] in
            guard let self else { return }
            self.navigator?.hideTaskDetail()
            self.applyBoardChange(self.board.removingTask(id: id))
        }
        detail.onClose = { [weak self] in self?.navigator?.hideTaskDetail() }
        taskDetail = detail
        navigator?.showTaskDetail(detail)
    }

    /// Правка из инспектора: модель и карточка на доске обновляются без пересборки колонок
    private func updateTaskFromDetail(_ task: BoardTask) {
        board = board.replacingTask(task)
        navigator?.didUpdateBoard(board)
        for column in columnsStack.arrangedSubviews.compactMap({ $0 as? BoardColumnView }) {
            if let card = column.cardViews.compactMap({ $0 as? TaskCardView }).first(where: { $0.taskID == task.id }) {
                card.apply(task: task)
            }
        }
    }

    private func moveTask(id: String, toBoardID boardID: String) {
        guard let found = board.task(withID: id) else { return }
        var task = found.task
        let target = navigator?.allBoards().first { $0.id == boardID }
        task.record("Перенёс(ла) на доску «\(target?.title ?? "")»")
        navigator?.hideTaskDetail()
        applyBoardChange(board.removingTask(id: id))
        navigator?.addTask(task, toBoardID: boardID)
    }

    private func duplicateTask(id: String) {
        guard let found = board.task(withID: id) else { return }
        var copy = BoardTask(
            title: found.task.title + " (копия)",
            subtitle: found.task.subtitle,
            tags: found.task.tags,
            isFlagged: found.task.isFlagged,
            assignee: found.task.assignee,
            dueDate: found.task.dueDate,
            checklist: found.task.checklist.map { ChecklistItem(title: $0.title, isDone: $0.isDone) }
        )
        copy.record("Создал(а) копию задачи «\(found.task.title)»")
        applyBoardChange(board.insertingTask(copy, inColumn: found.column, at: found.index + 1))
    }

    // MARK: - Перенос колонок

    /// Колонка, которую несут: её карточки собраны в стопку `stack` под пальцем,
    /// а сама колонка осталась «слотом» в `columnsStack` и переезжает между соседями
    private struct ColumnDrag {
        let column: BoardColumnView
        let sourceIndex: Int
        let stack: UIView
        let snapshots: [UIView]
    }

    private var columnDrag: ColumnDrag?
    private var dragLocation: CGPoint = .zero
    private var autoScrollLink: CADisplayLink?
    private let reorderFeedback = UISelectionFeedbackGenerator()

    private func handleColumnReorder(_ gesture: UILongPressGestureRecognizer, column: BoardColumnView) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            beginColumnDrag(column, at: location)
        case .changed:
            moveColumnDrag(to: location)
        case .ended, .cancelled, .failed:
            endColumnDrag()
        default:
            break
        }
    }

    /// `freshSnapshots` — карточку только что вернули на место, снимать нужно уже отрисованное состояние
    private func beginColumnDrag(_ column: BoardColumnView, at location: CGPoint, freshSnapshots: Bool = false) {
        guard columnDrag == nil, cardDrag == nil,
              let sourceIndex = columnsStack.arrangedSubviews.firstIndex(of: column)
        else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Скролл доски не должен перехватывать палец, пока несём стопку
        boardScroll.panGestureRecognizer.isEnabled = false

        let stack = UIView(frame: CGRect(origin: location, size: .zero))
        stack.isUserInteractionEnabled = false
        view.addSubview(stack)

        let sources = column.cardViews.isEmpty ? [column.headerView] : column.cardViews
        var snapshots: [UIView] = []
        for source in sources.reversed() {
            guard let snapshot = source.snapshotView(afterScreenUpdates: freshSnapshots) else { continue }
            snapshot.frame = source.convert(source.bounds, to: stack)
            snapshot.layer.shadowColor = UIColor.black.cgColor
            snapshot.layer.shadowOpacity = 0.12
            snapshot.layer.shadowRadius = 14
            snapshot.layer.shadowOffset = CGSize(width: 0, height: 6)
            stack.addSubview(snapshot)
            snapshots.insert(snapshot, at: 0)
        }
        column.setDragPlaceholder(true)
        columnDrag = ColumnDrag(column: column, sourceIndex: sourceIndex, stack: stack, snapshots: snapshots)
        dragLocation = location
        reorderFeedback.prepare()

        // Карточки съезжаются под палец в стопку: верхняя ровно, нижние чуть повёрнуты и сдвинуты
        let tilts: [CGFloat] = [0, -5, 4, -2.5]
        for (index, snapshot) in snapshots.enumerated() {
            let depth = min(index, tilts.count - 1)
            UIView.animate(
                withDuration: 0.45,
                delay: Double(index) * 0.025,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                snapshot.center = CGPoint(x: 0, y: CGFloat(depth) * 5)
                snapshot.transform = CGAffineTransform(rotationAngle: tilts[depth] * .pi / 180)
                    .scaledBy(x: 0.82, y: 0.82)
                snapshot.alpha = index < tilts.count ? 1 : 0
            }
        }
        startAutoScroll()
    }

    private func moveColumnDrag(to location: CGPoint) {
        guard let drag = columnDrag else { return }
        dragLocation = location
        drag.stack.center = location
        updateColumnDragTarget()
    }

    /// Ставит «слот» колонки туда, где сейчас палец, — соседи раздвигаются, как иконки в Dock
    private func updateColumnDragTarget() {
        guard let drag = columnDrag else { return }
        let x = view.convert(dragLocation, to: columnsStack).x
        let others = columnsStack.arrangedSubviews.filter { $0 !== drag.column }
        let target = others.filter { $0.frame.midX < x }.count
        guard columnsStack.arrangedSubviews.firstIndex(of: drag.column) != target else { return }
        reorderFeedback.selectionChanged()
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.columnsStack.insertArrangedSubview(drag.column, at: target)
            self.boardScroll.layoutIfNeeded()
        }
    }

    private func endColumnDrag() {
        guard let drag = columnDrag else { return }
        columnDrag = nil
        stopAutoScroll()
        boardScroll.panGestureRecognizer.isEnabled = true
        let destination = columnsStack.arrangedSubviews.firstIndex(of: drag.column) ?? drag.sourceIndex

        // Стопка раскладывается обратно: каждая карточка летит на своё место в колонке
        view.layoutIfNeeded()
        let targets = drag.column.cardViews.isEmpty ? [drag.column.headerView] : drag.column.cardViews
        let group = DispatchGroup()
        for (index, snapshot) in drag.snapshots.enumerated() {
            guard targets.indices.contains(index) else { continue }
            let frame = targets[index].convert(targets[index].bounds, to: drag.stack)
            group.enter()
            UIView.animate(
                withDuration: 0.5,
                delay: Double(index) * 0.04,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState]
            ) {
                snapshot.transform = .identity
                snapshot.frame = frame
                snapshot.alpha = 1
                snapshot.layer.shadowOpacity = 0
            } completion: { _ in
                group.leave()
            }
        }
        UIView.animate(withDuration: 0.25) {
            drag.column.headerView.alpha = 1
        }
        group.notify(queue: .main) { [weak self] in
            drag.column.setDragPlaceholder(false)
            drag.stack.removeFromSuperview()
            guard let self, destination != drag.sourceIndex else { return }
            self.applyBoardChange(self.board.movingColumn(from: drag.sourceIndex, to: destination), rebuild: false)
        }
    }

    // MARK: - Перенос задач внутри колонки

    /// Карточка, которую несут: её снимок `snapshot` едет под пальцем, а сама карточка
    /// осталась невидимым «слотом» и переезжает между соседями — и между колонками, — как иконка в Dock
    private struct CardDrag {
        /// Колонка, в которой слот сейчас
        var column: BoardColumnView
        let columnIndex: Int
        let card: UIView
        let sourceIndex: Int
        let snapshot: UIView
        let grabOffset: CGPoint
    }

    private var cardDrag: CardDrag?
    /// Долгое удержание поднятой карточки на месте превращает перенос задачи в перенос всей колонки
    private var columnPromotion: DispatchWorkItem?
    private var cardDragStartLocation: CGPoint = .zero
    private static let columnPromotionDelay: TimeInterval = 0.7
    private static let columnPromotionSlop: CGFloat = 10

    private func handleCardReorder(_ gesture: UILongPressGestureRecognizer, card: UIView, column: BoardColumnView) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .changed where columnDrag != nil:
            moveColumnDrag(to: location)
        case .ended where columnDrag != nil, .cancelled where columnDrag != nil, .failed where columnDrag != nil:
            endColumnDrag()
        case .began:
            // Жест висит на колонке, где карточку создали, а после переноса она лежит в другой —
            // берём колонку, в которой карточка сейчас
            let current = columnsStack.arrangedSubviews
                .compactMap { $0 as? BoardColumnView }
                .first { $0.cardsStackView === card.superview } ?? column
            beginCardDrag(card, in: current, at: location)
        case .changed:
            moveCardDrag(to: location)
        case .ended, .cancelled, .failed:
            endCardDrag()
        default:
            break
        }
    }

    private func beginCardDrag(_ card: UIView, in column: BoardColumnView, at location: CGPoint) {
        guard cardDrag == nil, columnDrag == nil,
              let columnIndex = columnsStack.arrangedSubviews.firstIndex(of: column),
              let sourceIndex = column.cardViews.firstIndex(of: card),
              let snapshot = card.snapshotView(afterScreenUpdates: false)
        else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        boardScroll.panGestureRecognizer.isEnabled = false

        snapshot.frame = card.convert(card.bounds, to: view)
        snapshot.isUserInteractionEnabled = false
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0
        snapshot.layer.shadowRadius = 16
        snapshot.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.addSubview(snapshot)
        card.alpha = 0

        cardDrag = CardDrag(
            column: column,
            columnIndex: columnIndex,
            card: card,
            sourceIndex: sourceIndex,
            snapshot: snapshot,
            grabOffset: CGPoint(x: location.x - snapshot.center.x, y: location.y - snapshot.center.y)
        )
        dragLocation = location
        cardDragStartLocation = location
        reorderFeedback.prepare()
        scheduleColumnPromotion()

        // Карточка «поднимается» над колонкой
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            snapshot.transform = CGAffineTransform(scaleX: 1.04, y: 1.04).rotated(by: -1.5 * .pi / 180)
            snapshot.layer.shadowOpacity = 0.16
        }
        startAutoScroll()
    }

    private func moveCardDrag(to location: CGPoint) {
        guard let drag = cardDrag else { return }
        if hypot(location.x - cardDragStartLocation.x, location.y - cardDragStartLocation.y) > Self.columnPromotionSlop {
            columnPromotion?.cancel()
            columnPromotion = nil
        }
        dragLocation = location
        drag.snapshot.center = CGPoint(x: location.x - drag.grabOffset.x, y: location.y - drag.grabOffset.y)
        updateCardDragTarget()
    }

    /// Ставит «слот» карточки туда, где сейчас её снимок: в колонку под пальцем и между соседними задачами
    private func updateCardDragTarget() {
        guard var drag = cardDrag else { return }
        let center = view.convert(drag.snapshot.center, to: columnsStack)
        let targetColumn = columnsStack.arrangedSubviews
            .compactMap { $0 as? BoardColumnView }
            .first { center.x >= $0.frame.minX - Self.columnSpacing / 2 && center.x <= $0.frame.maxX + Self.columnSpacing / 2 }
            ?? drag.column
        let stack = targetColumn.cardsStackView
        let y = view.convert(drag.snapshot.center, to: stack).y
        let others = stack.arrangedSubviews.filter { $0 !== drag.card }
        let target = others.filter { $0.frame.midY < y }.count
        let changesColumn = targetColumn !== drag.column
        guard changesColumn || stack.arrangedSubviews.firstIndex(of: drag.card) != target else { return }
        reorderFeedback.selectionChanged()
        let previousColumn = drag.column
        drag.column = targetColumn
        cardDrag = drag
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            // Старая колонка схлопывается, в новой задачи раздвигаются под карточку
            stack.insertArrangedSubview(drag.card, at: target)
            self.boardScroll.layoutIfNeeded()
        }
        if changesColumn {
            previousColumn.refreshCount()
            targetColumn.refreshCount()
        }
    }

    private func scheduleColumnPromotion() {
        columnPromotion?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.promoteCardDragToColumn()
        }
        columnPromotion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.columnPromotionDelay, execute: work)
    }

    /// Карточку держат на месте — опускаем её обратно и поднимаем всю колонку стопкой
    private func promoteCardDragToColumn() {
        columnPromotion = nil
        guard let drag = cardDrag else { return }
        cardDrag = nil
        stopAutoScroll()
        drag.card.alpha = 1
        drag.column.refreshCount()
        UIView.animate(withDuration: 0.15) {
            drag.snapshot.alpha = 0
        } completion: { _ in
            drag.snapshot.removeFromSuperview()
        }
        beginColumnDrag(drag.column, at: dragLocation, freshSnapshots: true)
    }

    private func endCardDrag() {
        columnPromotion?.cancel()
        columnPromotion = nil
        guard let drag = cardDrag else { return }
        cardDrag = nil
        stopAutoScroll()
        boardScroll.panGestureRecognizer.isEnabled = true
        let destination = drag.column.cardViews.firstIndex(of: drag.card) ?? drag.sourceIndex
        let destinationColumn = columnsStack.arrangedSubviews.firstIndex(of: drag.column) ?? drag.columnIndex

        // Карточка опускается в свой слот
        view.layoutIfNeeded()
        let frame = drag.card.convert(drag.card.bounds, to: view)
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            drag.snapshot.transform = .identity
            drag.snapshot.center = CGPoint(x: frame.midX, y: frame.midY)
            drag.snapshot.layer.shadowOpacity = 0
        } completion: { [weak self] _ in
            drag.card.alpha = 1
            drag.snapshot.removeFromSuperview()
            guard let self,
                  destinationColumn != drag.columnIndex || destination != drag.sourceIndex
            else { return }
            self.applyBoardChange(self.board.movingTask(
                fromColumn: drag.columnIndex, index: drag.sourceIndex,
                toColumn: destinationColumn, index: destination
            ), rebuild: false)
        }
    }

    // Автопрокрутка доски, когда стопку подносят к краю экрана
    private func startAutoScroll() {
        stopAutoScroll()
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
        autoScrollHoverStartX = nil
        autoScrollHoverStartY = nil
    }

    @objc private func autoScrollTick() {
        if cardDrag != nil {
            // Задачу можно унести и в колонку за краем экрана
            autoScrollVertically()
            autoScrollHorizontally()
            updateCardDragTarget()
            return
        }
        guard columnDrag != nil else { return }
        if autoScrollHorizontally() {
            updateColumnDragTarget()
        }
    }

    /// Зона у края экрана, где включается автопрокрутка, и задержка перед стартом:
    /// доска не должна уезжать, когда карточку просто кладут в крайнюю колонку
    private static let autoScrollEdge: CGFloat = 40
    private static let autoScrollHoverDelay: CFTimeInterval = 0.35
    private var autoScrollHoverStartX: CFTimeInterval?
    private var autoScrollHoverStartY: CFTimeInterval?

    /// Шаг прокрутки: 0 вне зоны и пока палец не задержался у края; дальше скорость плавно растёт
    private func autoScrollStep(
        position: CGFloat, lower: CGFloat, upper: CGFloat, hoverStart: inout CFTimeInterval?
    ) -> CGFloat {
        let edge = Self.autoScrollEdge
        let depth: CGFloat
        if position < lower + edge {
            depth = -(lower + edge - position)
        } else if position > upper - edge {
            depth = position - (upper - edge)
        } else {
            hoverStart = nil
            return 0
        }
        let now = CACurrentMediaTime()
        guard let start = hoverStart else {
            hoverStart = now
            return 0
        }
        let held = now - start - Self.autoScrollHoverDelay
        guard held > 0 else { return 0 }
        let ramp = CGFloat(min(1, held / 0.4))
        return max(-12, min(12, depth / 3)) * ramp
    }

    @discardableResult
    private func autoScrollHorizontally() -> Bool {
        let step = autoScrollStep(
            position: dragLocation.x,
            lower: view.safeAreaInsets.left,
            upper: view.bounds.width - view.safeAreaInsets.right,
            hoverStart: &autoScrollHoverStartX
        )
        guard step != 0 else { return false }
        let inset = boardScroll.adjustedContentInset
        let minX = -inset.left
        let maxX = max(minX, boardScroll.contentSize.width - boardScroll.bounds.width + inset.right)
        let x = min(max(boardScroll.contentOffset.x + step, minX), maxX)
        guard x != boardScroll.contentOffset.x else { return false }
        boardScroll.contentOffset.x = x
        return true
    }

    /// При переносе задачи — прокрутка доски вверх/вниз у краёв экрана
    private func autoScrollVertically() {
        let step = autoScrollStep(
            position: dragLocation.y,
            lower: view.safeAreaInsets.top,
            upper: view.bounds.height - view.safeAreaInsets.bottom,
            hoverStart: &autoScrollHoverStartY
        )
        guard step != 0 else { return }
        let inset = boardScroll.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, boardScroll.contentSize.height - boardScroll.bounds.height + inset.bottom)
        let y = min(max(boardScroll.contentOffset.y + step, minY), maxY)
        guard y != boardScroll.contentOffset.y else { return }
        boardScroll.contentOffset.y = y
    }

    /// `rebuild: false` — после переноса: колонки и карточки уже стоят на местах, меняется только модель.
    /// Пересборка посреди следующего переноса «отрывала» несомую карточку от колонок
    private func applyBoardChange(_ next: Board, rebuild: Bool = true) {
        board = next
        navigator?.didUpdateBoard(board)
        taskDetail?.refresh(board: board, boards: navigator?.allBoards() ?? [board])
        if rebuild {
            refreshBoardTitle()
            rebuildColumns()
        } else {
            // Без перестройки кнопок навбара — только текст заголовка
            boardSubtitleLabel.text = Self.taskCountLabel(board.taskCount)
        }
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    private func configureSidebarToggle() {
        closeButton = makeCapsuleButton(
            symbol: "xmark",
            action: nil,
            accessibilityLabel: "Закрыть"
        )
        sidebarToggleButton = makeCapsuleButton(
            symbol: "sidebar.left",
            action: #selector(showSidebar),
            accessibilityLabel: "Папки"
        )
    }

    private func makeCapsuleButton(symbol: String, action: Selector?, accessibilityLabel: String) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: .notesBarSymbol(symbol),
            style: .plain,
            target: action == nil ? nil : self,
            action: action
        )
        item.applyNotesAccent()
        item.accessibilityLabel = accessibilityLabel
        return item
    }

    private func makeViewModeButton(
        symbol: String,
        accessibilityLabel: String,
        action: Selector? = nil
    ) -> UIBarButtonItem {
        let image = UIImage.notesBarSymbol(symbol)
        let item = UIBarButtonItem(
            image: image,
            style: .plain,
            target: action == nil ? nil : self,
            action: action
        )
        item.tintColor = .notesAccent
        item.accessibilityLabel = accessibilityLabel
        return item
    }

    private static var leadingCapsuleGap: UIBarButtonItem {
        let gap = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        gap.width = 8
        gap.hidesSharedBackground = true
        return gap
    }

    /// Переключает кнопки «✕»/сайдбар в навбаре доски. С `coordinator` всё — кнопки и сдвиг
    /// заголовка — едет внутри системной анимации колонки, одной пружиной, как в «Почте»
    func setSidebarToggleVisible(_ visible: Bool, alongside coordinator: UIViewControllerTransitionCoordinator?) {
        guard showsSidebarToggle != visible else { return }
        showsSidebarToggle = visible
        guard let coordinator else {
            applyCollapsedSidebarButtons()
            navigationController?.navigationBar.layoutIfNeeded()
            alignBoardTitleWithFirstColumn()
            return
        }
        // Как в «Почте»: при открытии сайдбара кнопки «✕»/сайдбар убираются сразу — иначе навбар
        // успевает перенести их под новую безопасную зону, правее заголовка; при закрытии они
        // проявляются системной анимацией. Заголовок — отдельный view — просто едет сдвигом
        isSidebarTransitioning = true
        if !visible {
            UIView.performWithoutAnimation {
                applyCollapsedSidebarButtons()
                navigationController?.navigationBar.layoutIfNeeded()
            }
        }
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            if visible {
                self.applyCollapsedSidebarButtons()
                self.navigationController?.navigationBar.layoutIfNeeded()
            }
            self.view.layoutIfNeeded()
            self.alignBoardTitleWithFirstColumn()
        }, completion: { [weak self] _ in
            self?.isSidebarTransitioning = false
            self?.alignBoardTitleWithFirstColumn()
            // Навбар может доуложить кнопки чуть позже — перемеряем место заголовка
            for delay in [0.1, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let self, !self.isSidebarTransitioning else { return }
                    self.alignBoardTitleWithFirstColumn()
                }
            }
        })
    }

    private func applyCollapsedSidebarButtons() {
        rebuildLeadingBarItems()
    }

    private func rebuildLeadingBarItems() {
        navigationItem.leftBarButtonItem = nil
        navigationItem.leftBarButtonItems = nil
        var groups: [UIBarButtonItemGroup] = []
        if showsSidebarToggle, let close = closeButton, let sidebar = sidebarToggleButton {
            // Порядок как в шапке открытого сайдбара: «✕», «+ ⌄», сайдбар
            groups.append(UIBarButtonItemGroup(barButtonItems: [close], representativeItem: nil))
            groups.append(UIBarButtonItemGroup(barButtonItems: [Self.leadingCapsuleGap], representativeItem: nil))
            if addMenuButton == nil, let menu = navigator?.makeAddMenu() {
                addMenuButton = .notesAddMenuButton(menu: menu)
            }
            if let add = addMenuButton {
                groups.append(UIBarButtonItemGroup(barButtonItems: [add], representativeItem: nil))
                groups.append(UIBarButtonItemGroup(barButtonItems: [Self.leadingCapsuleGap], representativeItem: nil))
            }
            groups.append(UIBarButtonItemGroup(barButtonItems: [sidebar], representativeItem: nil))
            groups.append(UIBarButtonItemGroup(barButtonItems: [Self.leadingCapsuleGap], representativeItem: nil))
        }
        if let titleItem = boardTitleItem {
            groups.append(UIBarButtonItemGroup(barButtonItems: [titleItem], representativeItem: nil))
        }
        navigationItem.leadingItemGroups = groups
        // На iPhone доска открывается поверх сайдбара — кнопка «Назад» должна остаться
        navigationItem.leftItemsSupplementBackButton = true
        applyCenterBarItems()
        applyTrailingBarItems()
        navigationController?.navigationBar.applyNotesAccentToBarSymbols()
    }

    private func applyCenterBarItems() {
        navigationItem.style = .editor
        // iPhone: панель вида внизу экрана, в навбаре только поиск
        if prefersTitleInBar {
            navigationItem.centerItemGroups = []
            return
        }
        if let check = viewModeCheckButton,
           let board = viewModeBoardButton,
           let list = viewModeListButton,
           let more = viewModeMoreButton {
            var groups = [UIBarButtonItemGroup(barButtonItems: [check, board, list, more], representativeItem: nil)]
            if let addColumn = addColumnButton {
                groups.append(UIBarButtonItemGroup(barButtonItems: [addColumn], representativeItem: nil))
            }
            navigationItem.centerItemGroups = groups
        } else {
            navigationItem.centerItemGroups = []
        }
    }

    private func applyTrailingBarItems() {
        navigationItem.rightBarButtonItem = nil
        navigationItem.rightBarButtonItems = nil
        guard let search = searchButton else {
            navigationItem.trailingItemGroups = []
            return
        }
        navigationItem.trailingItemGroups = [
            UIBarButtonItemGroup(barButtonItems: [search], representativeItem: nil)
        ]
    }

    @objc private func showSidebar() {
        navigator?.showSidebarColumn()
    }

    @objc private func showFilters() {
        let sheet = FiltersViewController()
        sheet.modalPresentationStyle = .popover
        if let popover = sheet.popoverPresentationController {
            if prefersTitleInBar, let source = phoneFiltersButton {
                popover.sourceView = source
                popover.sourceRect = source.bounds
            } else {
                popover.sourceItem = viewModeListButton
            }
            popover.permittedArrowDirections = .any
            popover.delegate = self
        }
        present(sheet, animated: true)
    }
}
