import UIKit

final class SidebarViewController: UITableViewController {
    weak var navigator: TaskSplitNavigating?
    private var closeButton: UIBarButtonItem?
    private var addBoardItem: UIBarButtonItem?
    private var sidebarHideButton: UIBarButtonItem?
    private var boards = SidebarLayoutStore.loadBoards()
    private var smartCards = SidebarLayoutStore.loadSmartCards()
    private var selectedBoardID: String? = BoardSample.initial.id
    /// Выбранный пункт верхнего списка («Все задачи», …, «Архив»), если выбрана не доска
    private var selectedListItemID: String?
    private static let smartCardsSection = 0
    private static let boardsSection = 1
    private static let archiveItem = SidebarListItem(id: "archive", title: "Архив", symbolName: "archivebox", count: nil)

    /// Верхний список вне режима редактирования: видимые смарт-пункты и «Архив» последним
    private var listItems: [SidebarListItem] {
        smartCards.filter(\.isVisible).map(SidebarListItem.init(card:)) + [Self.archiveItem]
    }
    private let editButton = UIButton(type: .system)
    /// Где iOS поставила системный красный кружок удаления в строке доски
    /// (центр кружка и сдвиг содержимого). Смарт-карточки выравниваются по этим значениям.
    private var boardEditAlignment: (controlCenterX: CGFloat, contentInset: CGFloat)?
    private var alignmentUpdateScheduled = false

    init() {
        let style: UITableView.Style = UIDevice.current.userInterfaceIdiom == .pad ? .plain : .insetGrouped
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.applyNotesAccentAppearance()
        view.tintColor = .notesAccent
        tableView.register(BoardRowCell.self, forCellReuseIdentifier: BoardRowCell.reuseID)
        tableView.register(SidebarListCell.self, forCellReuseIdentifier: SidebarListCell.reuseID)
        tableView.register(SmartCardEditCell.self, forCellReuseIdentifier: SmartCardEditCell.reuseID)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "BoardsHeader")
        tableView.rowHeight = 52
        tableView.estimatedRowHeight = 52
        tableView.estimatedSectionHeaderHeight = 28
        tableView.separatorStyle = .none
        tableView.allowsSelectionDuringEditing = true
        configureBarButtons()
        configureEditButton()
        applyTaskCounts()
        applySplitChrome()
    }

    func allBoards() -> [Board] {
        boards
    }

    /// Смарт-списки со свежими счётчиками — для главного экрана iPhone
    func smartCardsForDisplay() -> [SidebarSmartCard] {
        applyTaskCounts()
        return smartCards
    }

    func setSmartCard(id: String, visible: Bool) {
        guard let index = smartCards.firstIndex(where: { $0.id == id }) else { return }
        smartCards[index].isVisible = visible
        SidebarLayoutStore.saveSmartCards(smartCards)
        if isViewLoaded { tableView.reloadData() }
    }

    func moveSmartCard(from source: Int, to destination: Int) {
        guard smartCards.indices.contains(source), smartCards.indices.contains(destination) else { return }
        smartCards.insert(smartCards.remove(at: source), at: destination)
        SidebarLayoutStore.saveSmartCards(smartCards)
        if isViewLoaded { tableView.reloadData() }
    }

    func removeBoard(id: String) {
        guard let row = boards.firstIndex(where: { $0.id == id }) else { return }
        deleteBoard(at: row)
    }

    func moveBoard(from source: Int, to destination: Int) {
        guard boards.indices.contains(source), boards.indices.contains(destination) else { return }
        boards.insert(boards.remove(at: source), at: destination)
        SidebarLayoutStore.saveBoards(boards)
        if isViewLoaded { tableView.reloadData() }
    }

    /// Задачу перенесли с другой доски — кладём её первой в первую колонку
    func addTask(_ task: BoardTask, toBoardID boardID: String) {
        guard let board = boards.first(where: { $0.id == boardID }) else { return }
        updateBoard(board.insertingTask(task, inColumn: 0, at: 0))
    }

    func updateBoard(_ board: Board) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            boards[index] = board
        }
        applyTaskCounts()
        guard isViewLoaded, !isEditing else { return }
        tableView.reloadSections(IndexSet(integer: Self.smartCardsSection), with: .none)
        restoreBoardSelection()
    }

    private func applyTaskCounts() {
        let total = boards.reduce(0) { $0 + $1.taskCount }
        let flagged = boards.reduce(0) { $0 + $1.flaggedTaskCount }
        for index in smartCards.indices {
            switch smartCards[index].id {
            case "all":
                smartCards[index].count = "\(total)"
            case "flagged":
                smartCards[index].count = "\(flagged)"
            default:
                break
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachEditButtonIfNeeded()
        layoutEditButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        attachEditButtonIfNeeded()
        layoutEditButton()
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutEditButton()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // На iPhone доска открывается в том же стеке — «Изменить» висит в общем контейнере, прячем
        if isCompactSplit {
            editButton.isHidden = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        editButton.isHidden = false
        navigationController?.navigationBar.applyNotesAccentAppearance()
        navigationController?.navigationBar.tintColor = .notesAccent
        view.tintColor = .notesAccent
        applySplitChrome()
        navigationController?.navigationBar.applyNotesAccentToBarSymbols()
        restoreBoardSelection()
    }

    private var isCompactSplit: Bool {
        splitViewController?.isCollapsed ?? true
    }

    private func applySplitChrome() {
        navigationItem.leftBarButtonItem = closeButton
        closeButton?.applyNotesAccent()
        addBoardItem?.applyNotesAccent()
        applyTrailingBarButtons()
        navigationController?.setToolbarHidden(true, animated: false)
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.prefersLargeTitles = false
        if isCompactSplit {
            tableView.backgroundColor = .systemGroupedBackground
            view.backgroundColor = .systemGroupedBackground
        } else {
            tableView.backgroundColor = .clear
            view.backgroundColor = .clear
            tableView.sectionHeaderTopPadding = 0
            tableView.contentInset.top = 0
            tableView.layoutMargins = .zero
            tableView.preservesSuperviewLayoutMargins = false
            tableView.insetsContentViewsToSafeArea = false
        }
    }

    private func configureBarButtons() {
        let closeImage = UIImage.notesBarGlyph("xmark")
        let closeButtonView = UIButton(type: .custom)
        closeButtonView.setImage(closeImage, for: .normal)
        closeButtonView.imageView?.contentMode = .center
        closeButtonView.frame = CGRect(x: 0, y: 0, width: 34, height: 44)
        closeButtonView.addTarget(self, action: #selector(closeSidebar), for: .touchUpInside)
        closeButtonView.accessibilityLabel = "Закрыть"
        let close = UIBarButtonItem(customView: closeButtonView)
        closeButton = close
        navigationItem.leftBarButtonItem = close

        addBoardItem = .notesAddMenuButton(menu: makeAddMenu())

        // Обычный bar item — система рисует ему собственный стеклянный бабл
        let sidebar = UIBarButtonItem(
            image: .notesBarSymbol("sidebar.left"),
            style: .plain,
            target: self,
            action: #selector(closeSidebar)
        )
        sidebar.accessibilityLabel = "Папки"
        sidebar.applyNotesAccent()
        sidebarHideButton = sidebar
        applyTrailingBarButtons()
    }

    /// Меню «+ ⌄»: общее для шапки сайдбара и навбара доски при закрытом сайдбаре
    func makeAddMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: "Создать доску",
                image: UIImage(systemName: "mail.stack")
            ) { [weak self] _ in
                self?.presentNewBoard()
            },
            UIAction(
                title: "Создать задачу",
                image: UIImage(systemName: "list.bullet")
            ) { _ in },
            UIAction(
                title: "Добавить папку",
                image: UIImage(systemName: "folder.badge.plus")
            ) { _ in }
        ])
    }

    private static let barCapsuleHeight: CGFloat = 44

    private func configureEditButton() {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.baseForegroundColor = .notesAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        editButton.configuration = config
        updateEditButtonTitle()
        editButton.addTarget(self, action: #selector(toggleEdit), for: .touchUpInside)
        tableView.contentInset.bottom = 64
    }

    private func updateEditButtonTitle() {
        var title = AttributedString(isEditing ? "Готово" : "Изменить")
        title.font = .systemFont(ofSize: 17, weight: isEditing ? .semibold : .regular)
        editButton.configuration?.attributedTitle = title
        layoutEditButton()
    }

    private func attachEditButtonIfNeeded() {
        guard let host = navigationController?.view else { return }
        if editButton.superview !== host {
            editButton.removeFromSuperview()
            host.addSubview(editButton)
        }
    }

    /// Кнопка «Изменить» висит внизу сайдбара, по левому краю — на месте, симметричном крестику в шапке.
    /// Высота совпадает со стеклянными капсулами навбара.
    private func layoutEditButton() {
        guard let host = navigationController?.view else { return }
        let closeView = closeButton?.customView
        let closeFrame = closeView.map { $0.convert($0.bounds, to: host) } ?? CGRect(
            x: 16,
            y: 10,
            width: 34,
            height: 44
        )
        let height = Self.barCapsuleHeight
        let fitting = editButton.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: height)).width
        editButton.frame = CGRect(
            x: closeFrame.minX,
            y: host.bounds.height - closeFrame.midY - height / 2,
            width: max(fitting, height),
            height: height
        )
        host.bringSubviewToFront(editButton)
    }

    private func applyTrailingBarButtons() {
        guard let add = addBoardItem else { return }
        navigationItem.rightBarButtonItem = nil
        // «+⌄» и сайдбар — два отдельных стеклянных бабла, а не одна общая капсула
        var groups = [UIBarButtonItemGroup(barButtonItems: [add], representativeItem: nil)]
        if let sidebar = sidebarHideButton {
            sidebar.sharesBackground = false
            groups.append(UIBarButtonItemGroup(barButtonItems: [sidebar], representativeItem: nil))
        }
        navigationItem.trailingItemGroups = groups
    }

    private func presentNewBoard() {
        let sheet = NewBoardViewController()
        sheet.onCreate = { [weak self] board in
            guard let self else { return }
            self.boards.insert(board, at: 0)
            SidebarLayoutStore.saveBoards(self.boards)
            self.applyTaskCounts()
            self.tableView.reloadData()
            self.selectedBoardID = board.id
            self.navigator?.didSelectBoard(board)
            self.restoreBoardSelection()
        }
        sheet.modalPresentationStyle = .formSheet
        sheet.preferredContentSize = CGSize(width: 540, height: 760)
        (splitViewController ?? navigationController ?? self).present(sheet, animated: true)
    }

    @objc private func closeSidebar() {
        if let split = splitViewController, !split.isCollapsed {
            split.hide(.primary)
            navigator?.didHideSidebar()
        } else {
            navigator?.hideSidebarColumn()
        }
    }

    @objc private func toggleEdit() {
        setEditing(!isEditing, animated: true)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        if !editing {
            SidebarLayoutStore.saveBoards(boards)
            SidebarLayoutStore.saveSmartCards(smartCards)
        }
        super.setEditing(editing, animated: animated)
        updateEditButtonTitle()
        tableView.reloadData()
        if !editing {
            applyTaskCounts()
            restoreBoardSelection()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Self.smartCardsSection:
            return isEditing ? smartCards.count : listItems.count
        default:
            return boards.count
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == Self.smartCardsSection && !isEditing
            ? SidebarMetrics.listRowHeight
            : SidebarMetrics.rowHeight
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard section == Self.boardsSection, showsBoardsHeader else { return .leastNormalMagnitude }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == Self.boardsSection, showsBoardsHeader else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "BoardsHeader")
        header?.preservesSuperviewLayoutMargins = false
        header?.contentView.preservesSuperviewLayoutMargins = false
        header?.insetsLayoutMarginsFromSafeArea = false
        var content = UIListContentConfiguration.sidebarHeader()
        content.text = "Доски"
        content.textProperties.font = .sectionHeader
        content.textProperties.color = .secondaryLabel
        content.axesPreservingSuperviewLayoutMargins = []
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: SidebarMetrics.iconLeading,
            bottom: 6,
            trailing: 16
        )
        header?.contentConfiguration = content
        header?.backgroundConfiguration = .clear()
        return header
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Self.smartCardsSection, !isEditing {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SidebarListCell.reuseID,
                for: indexPath
            ) as! SidebarListCell
            cell.apply(item: listItems[indexPath.row], showsDisclosure: isCompactSplit)
            return cell
        }
        if indexPath.section == Self.smartCardsSection {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SmartCardEditCell.reuseID,
                for: indexPath
            ) as! SmartCardEditCell
            cell.apply(card: smartCards[indexPath.row])
            if let alignment = boardEditAlignment {
                cell.applyEditingAlignment(controlCenterX: alignment.controlCenterX, contentInset: alignment.contentInset)
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: BoardRowCell.reuseID, for: indexPath) as! BoardRowCell
        let board = boards[indexPath.row]
        cell.apply(board: board, showsDisclosure: isCompactSplit && !isEditing)
        cell.setEditingMenu(makeBoardMenu(for: board))
        cell.onEditingLayout = { [weak self] controlCenterX, contentInset in
            self?.boardCellDidLayoutEditing(controlCenterX: controlCenterX, contentInset: contentInset)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            if indexPath.section == Self.smartCardsSection {
                toggleSmartCard(at: indexPath.row)
            }
            tableView.deselectRow(at: indexPath, animated: false)
            return
        }
        if indexPath.section == Self.smartCardsSection {
            selectedListItemID = listItems[indexPath.row].id
            selectedBoardID = nil
            if isCompactSplit {
                tableView.deselectRow(at: indexPath, animated: true)
            }
            return
        }
        let board = boards[indexPath.row]
        selectedBoardID = board.id
        selectedListItemID = nil
        if isCompactSplit {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        navigator?.didSelectBoard(board)
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if isEditing {
            return indexPath.section == Self.smartCardsSection
        }
        return true
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.setEditing(isEditing, animated: false)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Self.boardsSection || isEditing
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        indexPath.section == Self.boardsSection ? .delete : .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Self.boardsSection
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, indexPath.section == Self.boardsSection else { return }
        deleteBoard(at: indexPath.row)
    }

    // MARK: - Выравнивание смарт-карточек по системному контролу удаления

    private func boardCellDidLayoutEditing(controlCenterX: CGFloat, contentInset: CGFloat) {
        if let current = boardEditAlignment,
           abs(current.controlCenterX - controlCenterX) < 0.5,
           abs(current.contentInset - contentInset) < 0.5 {
            return
        }
        boardEditAlignment = (controlCenterX, contentInset)
        // Вызывается из layoutSubviews ячейки — применяем на следующем цикле,
        // чтобы не трогать таблицу посреди её собственной раскладки.
        guard !alignmentUpdateScheduled else { return }
        alignmentUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.alignmentUpdateScheduled = false
            guard let alignment = self.boardEditAlignment else { return }
            for row in 0..<self.tableView.numberOfRows(inSection: Self.smartCardsSection) {
                let indexPath = IndexPath(row: row, section: Self.smartCardsSection)
                (self.tableView.cellForRow(at: indexPath) as? SmartCardEditCell)?
                    .applyEditingAlignment(controlCenterX: alignment.controlCenterX, contentInset: alignment.contentInset)
            }
        }
    }

    // MARK: - Меню доски (три точки в режиме «Изменить»)

    private func makeBoardMenu(for board: Board) -> UIMenu {
        let boardID = board.id
        let edit = UIAction(
            title: "Изменить",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.presentEditBoard(id: boardID)
        }
        let delete = UIAction(
            title: "Удалить",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let index = self.boards.firstIndex(where: { $0.id == boardID }) else { return }
            self.deleteBoard(at: index)
        }
        return UIMenu(children: [edit, delete])
    }

    private func presentEditBoard(id: String) {
        guard let board = boards.first(where: { $0.id == id }) else { return }
        let sheet = NewBoardViewController()
        sheet.editingBoard = board
        sheet.onCreate = { [weak self] updated in
            guard let self, let index = self.boards.firstIndex(where: { $0.id == updated.id }) else { return }
            self.boards[index] = updated
            SidebarLayoutStore.saveBoards(self.boards)
            self.applyTaskCounts()
            self.tableView.reloadRows(
                at: [IndexPath(row: index, section: Self.boardsSection)],
                with: .none
            )
            if self.selectedBoardID == updated.id, !self.isCompactSplit {
                self.navigator?.didSelectBoard(updated)
            }
        }
        sheet.modalPresentationStyle = .formSheet
        sheet.preferredContentSize = CGSize(width: 540, height: 760)
        (splitViewController ?? navigationController ?? self).present(sheet, animated: true)
    }

    private func deleteBoard(at row: Int) {
        guard boards.indices.contains(row) else { return }
        let indexPath = IndexPath(row: row, section: Self.boardsSection)
        let removed = boards.remove(at: row)
        if isViewLoaded, tableView.window != nil {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        } else if isViewLoaded {
            tableView.reloadData()
        }
        SidebarLayoutStore.saveBoards(boards)
        applyTaskCounts()
        if selectedBoardID == removed.id {
            if boards.indices.contains(indexPath.row) {
                let next = boards[indexPath.row]
                selectedBoardID = next.id
                navigator?.didSelectBoard(next)
            } else if let last = boards.last {
                selectedBoardID = last.id
                navigator?.didSelectBoard(last)
            } else {
                selectedBoardID = nil
            }
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Self.smartCardsSection || indexPath.section == Self.boardsSection
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        if sourceIndexPath.section == Self.smartCardsSection {
            let card = smartCards.remove(at: sourceIndexPath.row)
            smartCards.insert(card, at: destinationIndexPath.row)
        } else if sourceIndexPath.section == Self.boardsSection {
            let board = boards.remove(at: sourceIndexPath.row)
            boards.insert(board, at: destinationIndexPath.row)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedDestinationIndexPath.section == sourceIndexPath.section else {
            if proposedDestinationIndexPath.section < sourceIndexPath.section {
                return IndexPath(row: 0, section: sourceIndexPath.section)
            }
            let last = max(tableView.numberOfRows(inSection: sourceIndexPath.section) - 1, 0)
            return IndexPath(row: last, section: sourceIndexPath.section)
        }
        return proposedDestinationIndexPath
    }

    private func toggleSmartCard(at index: Int) {
        guard smartCards.indices.contains(index) else { return }
        smartCards[index].isVisible.toggle()
        let indexPath = IndexPath(row: index, section: Self.smartCardsSection)
        if let cell = tableView.cellForRow(at: indexPath) as? SmartCardEditCell {
            cell.apply(card: smartCards[index])
        }
    }

    private var showsBoardsHeader: Bool { true }

    private func restoreBoardSelection() {
        guard !isCompactSplit, !isEditing else { return }
        if selectedBoardID == nil {
            guard let row = listItems.firstIndex(where: { $0.id == selectedListItemID }) else { return }
            tableView.selectRow(
                at: IndexPath(row: row, section: Self.smartCardsSection),
                animated: false,
                scrollPosition: .none
            )
            return
        }
        guard let row = boards.firstIndex(where: { $0.id == selectedBoardID }) else { return }
        tableView.selectRow(
            at: IndexPath(row: row, section: Self.boardsSection),
            animated: false,
            scrollPosition: .none
        )
    }
}

/// Размеры строк сайдбара, сняты с нативных приложений iPadOS на iPad Pro 13":
/// доски с цветными плашками — как в «Настройках», верхний список с контурными иконками — как в «Файлах»/«Почте»
private enum SidebarMetrics {
    static let rowHeight: CGFloat = 52
    static let listRowHeight: CGFloat = 44
    static let iconLeading: CGFloat = 30
    static let iconSize: CGFloat = ListIconStyle.plateSize
    static let titleGap: CGFloat = 8
    static let pillHorizontalInset: CGFloat = 16
    static let pillVerticalInset: CGFloat = 1
}

private struct SidebarListItem {
    let id: String
    let title: String
    let symbolName: String
    let count: String?

    init(id: String, title: String, symbolName: String, count: String?) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.count = count
    }

    /// Плитки рисовали залитые иконки на цветной подложке, в списке — контурные, как в сайдбарах iPadOS
    init(card: SidebarSmartCard) {
        let symbol = card.symbolName == "checkmark"
            ? "checkmark.circle"
            : card.symbolName.replacingOccurrences(of: ".fill", with: "")
        self.init(id: card.id, title: card.title, symbolName: symbol, count: card.count)
    }
}

/// Пункт верхнего списка сайдбара: зелёная иконка слева, название, счётчик справа.
private final class SidebarListCell: UITableViewCell {
    static let reuseID = "SidebarList"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let selectionPill = SidebarSelectionPill()
    private var showsDisclosure = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        focusEffect = nil
        automaticallyUpdatesBackgroundConfiguration = false
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        insetsLayoutMarginsFromSafeArea = false

        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(selectionPill, at: 0)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        iconView.tintColor = .notesAccent
        iconView.preferredSymbolConfiguration = ListIconStyle.lineSymbolConfiguration

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 15, weight: .regular)
        countLabel.textColor = .secondaryLabel
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            // Та же ось, что у иконок досок (плашка 29 pt с отступом 22 pt)
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SidebarMetrics.iconLeading),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: SidebarMetrics.titleGap),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),

            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SidebarMetrics.iconLeading),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            selectionPill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SidebarMetrics.pillVerticalInset),
            selectionPill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SidebarMetrics.pillVerticalInset),
            selectionPill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SidebarMetrics.pillHorizontalInset),
            selectionPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SidebarMetrics.pillHorizontalInset)
        ])
    }

    override var canBecomeFocused: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(item: SidebarListItem, showsDisclosure: Bool) {
        self.showsDisclosure = showsDisclosure
        accessoryType = showsDisclosure ? .disclosureIndicator : .none
        iconView.image = UIImage(systemName: item.symbolName)
        titleLabel.text = item.title
        countLabel.text = item.count
        countLabel.isHidden = item.count == nil || showsDisclosure
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        let selected = (state.isSelected || state.isHighlighted) && !showsDisclosure && !state.isEditing
        titleLabel.font = .systemFont(ofSize: 17, weight: selected ? .semibold : .regular)
        backgroundConfiguration = .clear()
        selectionPill.isHidden = !selected
    }
}

/// Серая капсула выделения активного пункта сайдбара
private final class SidebarSelectionPill: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Лёгкий серый, как выделение в нативных сайдбарах iPadOS
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.07)
        }
        layer.cornerCurve = .continuous
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

private final class SmartCardEditCell: UITableViewCell {
    static let reuseID = "SmartCardEdit"

    private let checkbox = UIButton(type: .system)
    private let iconPlate = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var checkboxCenterX: NSLayoutConstraint!
    private var iconLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        focusEffect = nil
        automaticallyUpdatesBackgroundConfiguration = false
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        insetsLayoutMarginsFromSafeArea = false

        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.isUserInteractionEnabled = false
        checkbox.accessibilityLabel = "Показать карточку"

        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.clipsToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label

        contentView.addSubview(checkbox)
        contentView.addSubview(iconPlate)
        iconPlate.addSubview(iconView)
        contentView.addSubview(titleLabel)

        checkboxCenterX = checkbox.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30)
        iconLeading = iconPlate.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 54)

        NSLayoutConstraint.activate([
            checkboxCenterX,
            checkbox.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 28),
            checkbox.heightAnchor.constraint(equalToConstant: 28),

            iconLeading,
            iconPlate.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),
            iconPlate.heightAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),

            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarMetrics.iconSize * ListIconStyle.glyphRatio),
            iconView.heightAnchor.constraint(equalToConstant: SidebarMetrics.iconSize * ListIconStyle.glyphRatio),

            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: SidebarMetrics.titleGap),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconPlate.layer.cornerRadius = iconPlate.bounds.width * GradientIconPlate.cornerRatio
        iconPlate.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Ставит чекбокс по центру системного красного кружка досок,
    /// а аватар — на ту же ось, что и аватары досок (сдвиг iOS + SidebarMetrics.iconLeading, как в BoardRowCell).
    func applyEditingAlignment(controlCenterX: CGFloat, contentInset: CGFloat) {
        let newIconLeading = contentInset + SidebarMetrics.iconLeading
        guard abs(checkboxCenterX.constant - controlCenterX) >= 0.5
                || abs(iconLeading.constant - newIconLeading) >= 0.5 else { return }
        checkboxCenterX.constant = controlCenterX
        iconLeading.constant = newIconLeading
        setNeedsLayout()
    }

    func apply(card: SidebarSmartCard) {
        titleLabel.text = card.editTitle
        iconPlate.backgroundColor = card.bottomColor
        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.appSymbolWeight)
        iconView.image = UIImage(systemName: card.symbolName, withConfiguration: symbol)?
            .withRenderingMode(.alwaysTemplate)
        let checkConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: UIImage.appSymbolWeight)
        if card.isVisible {
            checkbox.setImage(
                UIImage(systemName: "checkmark.circle.fill", withConfiguration: checkConfig),
                for: .normal
            )
            checkbox.tintColor = .notesAccent
        } else {
            checkbox.setImage(
                UIImage(systemName: "circle", withConfiguration: checkConfig),
                for: .normal
            )
            checkbox.tintColor = .tertiaryLabel
        }
        backgroundConfiguration = .clear()
    }
}

private final class BoardRowCell: UITableViewCell {
    static let reuseID = "Board"

    private let iconPlate = GradientIconPlate()
    private let iconView = UIImageView()
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let selectionPill = SidebarSelectionPill()
    private var board: Board?
    private var showsDisclosure = false
    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis.circle", withConfiguration: UIImage.SymbolConfiguration(weight: UIImage.appSymbolWeight)),
            for: .normal
        )
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "Действия с доской"
        button.sizeToFit()
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        editingAccessoryView = moreButton
        selectionStyle = .none
        backgroundColor = .clear
        focusEffect = nil
        automaticallyUpdatesBackgroundConfiguration = false
        preservesSuperviewLayoutMargins = false
        contentView.preservesSuperviewLayoutMargins = false
        insetsLayoutMarginsFromSafeArea = false

        let pill = selectionPill
        pill.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(pill, at: 0)

        iconPlate.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = .systemFont(ofSize: 18)
        emojiLabel.textAlignment = .center
        emojiLabel.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label

        contentView.addSubview(iconPlate)
        iconPlate.addSubview(iconView)
        iconPlate.addSubview(emojiLabel)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconPlate.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SidebarMetrics.iconLeading),
            iconPlate.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),
            iconPlate.heightAnchor.constraint(equalToConstant: SidebarMetrics.iconSize),

            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarMetrics.iconSize * ListIconStyle.glyphRatio),
            iconView.heightAnchor.constraint(equalToConstant: SidebarMetrics.iconSize * ListIconStyle.glyphRatio),

            emojiLabel.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: SidebarMetrics.titleGap),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            pill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: SidebarMetrics.pillVerticalInset),
            pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -SidebarMetrics.pillVerticalInset),
            pill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: SidebarMetrics.pillHorizontalInset),
            pill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SidebarMetrics.pillHorizontalInset)
        ])
    }

    override var canBecomeFocused: Bool { false }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Сообщает центр системного контрола удаления и сдвиг содержимого в режиме редактирования.
    var onEditingLayout: ((_ controlCenterX: CGFloat, _ contentInset: CGFloat) -> Void)?

    func setEditingMenu(_ menu: UIMenu) {
        moreButton.menu = menu
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isEditing else { return }
        let inset = contentView.frame.minX
        guard inset > 1 else { return }
        // Системный контрол удаления iOS — это UIControl слева от contentView.
        let editControl = subviews.first {
            $0 !== contentView && $0 is UIControl && !$0.isHidden && $0.frame.maxX <= inset + 1
        }
        let centerX = editControl?.frame.midX ?? inset / 2
        onEditingLayout?(centerX.rounded(), inset.rounded())
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onEditingLayout = nil
    }

    func apply(board: Board, showsDisclosure: Bool) {
        self.board = board
        self.showsDisclosure = showsDisclosure
        accessoryType = showsDisclosure ? .disclosureIndicator : .none
        titleLabel.text = board.title
        iconPlate.apply(top: board.iconTop, bottom: board.iconBottom)
        if let emoji = board.emoji, !emoji.isEmpty {
            emojiLabel.text = emoji
            emojiLabel.isHidden = false
            iconView.isHidden = true
        } else {
            emojiLabel.isHidden = true
            iconView.isHidden = false
            iconView.image = Self.icon(for: board)
        }
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        guard let board else { return }
        let selected = (state.isSelected || state.isHighlighted) && !showsDisclosure && !state.isEditing
        titleLabel.font = .systemFont(ofSize: 17, weight: selected ? .semibold : .regular)
        titleLabel.textColor = .label
        iconPlate.apply(top: board.iconTop, bottom: board.iconBottom)
        iconView.tintColor = .white

        backgroundConfiguration = .clear()
        selectionPill.isHidden = !selected
    }

    private static func icon(for board: Board) -> UIImage? {
        if board.symbolName == "columns-3" {
            return UIImage(named: "columns-3")?.withRenderingMode(.alwaysTemplate)
        }
        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.appSymbolWeight)
        return UIImage(systemName: board.symbolName, withConfiguration: symbol)?
            .withRenderingMode(.alwaysTemplate)
    }
}

final class GradientIconPlate: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.insertSublayer(gradient, at: 0)
        clipsToBounds = true
        layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(top: UIColor, bottom: UIColor) {
        gradient.colors = [top.cgColor, bottom.cgColor]
    }

    /// Скругление квадратной иконки, как у иконок в «Настройках» iPadOS (~27% стороны)
    static let cornerRatio: CGFloat = 0.27

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        let radius = min(bounds.width, bounds.height) * Self.cornerRatio
        layer.cornerRadius = radius
        gradient.cornerRadius = radius
    }
}
