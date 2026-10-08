import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Карточка задачи в нативной колонке-инспекторе справа (UISplitViewController.Column.inspector).
/// На iPhone система показывает её листом.
/// Акцент открытой карточки задачи: её строки, кнопки и экран тегов собираются уже в этом цвете
enum DetailTheme {
    static var accent: UIColor = .notesAccent
}

final class TaskDetailViewController: UIViewController {
    private(set) var task: BoardTask
    private var board: Board
    private var boards: [Board]

    var onChange: ((BoardTask) -> Void)?
    var onMoveToColumn: ((Int) -> Void)?
    var onMoveToBoard: ((String) -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?
    var onClose: (() -> Void)?

    private enum ActivityTab: Int, CaseIterable {
        case comments, history, files, links

        var title: String {
            switch self {
            case .comments: return "Комментарии"
            case .history: return "История"
            case .files: return "Файлы"
            case .links: return "Связи"
            }
        }

        var symbol: String {
            switch self {
            case .comments: return "bubble.left.and.bubble.right"
            case .history: return "clock.arrow.circlepath"
            case .files: return "doc"
            case .links: return "link"
            }
        }
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleView = UITextView()
    private let titlePlaceholder = UILabel()
    private let descriptionView = UITextView()
    private let descriptionPlaceholder = UILabel()
    private let createdLabel = UILabel()
    private var settingsGroup = UIView()
    private var checklistGroup = UIView()
    private let checklistHeader = UILabel()
    private let checklistProgress = UILabel()
    private let segment = TabStripControl(items: ActivityTab.allCases.map { ($0.title, $0.symbol) })
    private var activityGroup = UIView()
    // lazy: собирается после того, как init выставил цвет карточки
    private lazy var composer = CommentComposerView()
    private var flagItem: UIBarButtonItem?
    private var composerBottom: NSLayoutConstraint!

    /// `accent` — цвет иконок и кнопок. На iPhone это цвет доски, на iPad — фирменный зелёный
    init(task: BoardTask, board: Board, boards: [Board], accent: UIColor = .notesAccent) {
        DetailTheme.accent = accent
        self.task = task
        self.board = board
        self.boards = boards
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .detailBackground
        view.tintColor = DetailTheme.accent
        configureNavigationItems()
        configureLayout()
        configureHeader()
        rebuildAll()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        alignComposerWithBottomButtons()
    }

    /// Центр поля комментария отстоит от низа экрана так же, как центр навбара — от верха:
    /// по этому же правилу стоит «Изменить» в сайдбаре
    private func alignComposerWithBottomButtons() {
        guard let bar = navigationController?.navigationBar, bar.window != nil else { return }
        let barMidY = bar.convert(CGPoint(x: 0, y: bar.bounds.midY), to: view).y
        guard barMidY > 0 else { return }
        // Нижний отступ композера 12 pt + половина поля
        let constant = -(barMidY - 12 - TaskDetailViewController.bubbleHeight / 2)
        if abs(composerBottom.constant - constant) > 0.5 {
            composerBottom.constant = constant
        }
    }

    /// Доска поменялась снаружи (перенос карточки, другая колонка) — обновляем то, что зависит от неё
    func refresh(board: Board, boards: [Board]) {
        self.board = board
        self.boards = boards
        guard let found = board.task(withID: task.id) else { return }
        task = found.task
        replace(&settingsGroup, with: makeSettingsGroup())
        updateFlagItem()
    }

    // MARK: - Навигация: «✕», флажок, «⋯»

    private func configureNavigationItems() {
        let close = UIBarButtonItem(
            image: UIImage.notesBarGlyph("xmark")?.withTintColor(DetailTheme.accent, renderingMode: .alwaysOriginal),
            primaryAction: UIAction { [weak self] _ in self?.onClose?() }
        )
        close.accessibilityLabel = "Закрыть"
        navigationItem.leftBarButtonItem = close
        let flag = UIBarButtonItem(
            image: nil,
            primaryAction: UIAction { [weak self] _ in self?.toggleFlag() }
        )
        flagItem = flag
        let more = UIBarButtonItem(
            image: UIImage.notesBarGlyph("ellipsis")?.withTintColor(DetailTheme.accent, renderingMode: .alwaysOriginal),
            menu: makeMoreMenu()
        )
        more.accessibilityLabel = "Ещё"
        navigationItem.rightBarButtonItems = [more, flag]
        updateFlagItem()
    }

    private func updateFlagItem() {
        let name = task.isFlagged ? "flag.fill" : "flag"
        flagItem?.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.barSymbolWeight)
        // Активный — залитый жёлтый, неактивный — зелёный контур
        )?.withTintColor(task.isFlagged ? .flag : DetailTheme.accent, renderingMode: .alwaysOriginal)
        flagItem?.accessibilityLabel = task.isFlagged ? "Снять флажок" : "Пометить флажком"
    }

    private func makeMoreMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Дублировать", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                self?.onDuplicate?()
            },
            UIAction(title: "Скопировать название", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                UIPasteboard.general.string = self?.task.title
            },
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Удалить задачу", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.confirmDelete()
                }
            ])
        ])
    }

    private func toggleFlag() {
        task.isFlagged.toggle()
        task.record(task.isFlagged ? "Поставил(а) флажок" : "Снял(а) флажок")
        updateFlagItem()
        commit()
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Удалить задачу?", message: task.title, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in self?.onDelete?() })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.popoverPresentationController?.sourceItem = navigationItem.rightBarButtonItems?.first
        present(alert, animated: true)
    }

    // MARK: - Раскладка

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        composer.translatesAutoresizingMaskIntoConstraints = false
        composerBottom = composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        composer.onSend = { [weak self] text, attachment in self?.addComment(text: text, attachment: attachment) }
        composer.onAttach = { [weak self] source in self?.pickAttachment(source) }
        view.addSubview(composer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: composer.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),

            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottom
        ])
        // Без клавиатуры направляющая стоит у самого низа экрана — поле ровняем по капсуле луп
        view.keyboardLayoutGuide.usesBottomSafeArea = false
    }

    private func rebuildAll() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        createdLabel.font = Self.captionFont
        createdLabel.textColor = .secondaryLabel
        createdLabel.text = "Создано: " + Self.createdText(task.createdAt)
        contentStack.addArrangedSubview(Self.inset(createdLabel, leading: 16))
        contentStack.setCustomSpacing(8, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makeHeaderGroup())

        settingsGroup = makeSettingsGroup()
        contentStack.addArrangedSubview(settingsGroup)

        checklistHeader.text = "Чек-лист"
        checklistHeader.font = Self.captionFont
        checklistHeader.textColor = .secondaryLabel
        checklistProgress.font = Self.captionFont
        checklistProgress.textColor = .secondaryLabel
        let checklistTitle = UIStackView(arrangedSubviews: [checklistHeader, UIView(), checklistProgress])
        checklistTitle.alignment = .lastBaseline
        contentStack.addArrangedSubview(Self.inset(checklistTitle, leading: 16, trailing: 16))
        contentStack.setCustomSpacing(8, after: checklistTitle.superview!)
        checklistGroup = makeChecklistGroup()
        contentStack.addArrangedSubview(checklistGroup)

        if segment.selectedSegmentIndex < 0 { segment.selectedSegmentIndex = ActivityTab.comments.rawValue }
        segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segment.heightAnchor.constraint(equalToConstant: Self.bubbleHeight).isActive = true
        contentStack.addArrangedSubview(segment)
        contentStack.setCustomSpacing(12, after: segment)
        activityGroup = makeActivityGroup()
        contentStack.addArrangedSubview(activityGroup)
    }

    private func replace(_ old: inout UIView, with new: UIView) {
        guard let index = contentStack.arrangedSubviews.firstIndex(of: old) else { return }
        let spacing = contentStack.customSpacing(after: old)
        old.removeFromSuperview()
        contentStack.insertArrangedSubview(new, at: index)
        if spacing != UIStackView.spacingUseDefault { contentStack.setCustomSpacing(spacing, after: new) }
        old = new
    }

    private func commit() {
        onChange?(task)
    }

    // MARK: - Заголовок и описание

    private func configureHeader() {
        // Название в несколько строк, как заголовок события в «Календаре»
        titleView.font = .systemFont(ofSize: 20, weight: .semibold)
        titleView.backgroundColor = .clear
        titleView.isScrollEnabled = false
        titleView.textContainerInset = .zero
        titleView.textContainer.lineFragmentPadding = 0
        titleView.returnKeyType = .next
        titleView.delegate = self
        titlePlaceholder.text = "Название"
        titlePlaceholder.font = titleView.font
        titlePlaceholder.textColor = .placeholderText
        titlePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        titleView.addSubview(titlePlaceholder)
        NSLayoutConstraint.activate([
            titlePlaceholder.topAnchor.constraint(equalTo: titleView.topAnchor),
            titlePlaceholder.leadingAnchor.constraint(equalTo: titleView.leadingAnchor)
        ])

        descriptionView.font = .preferredFont(forTextStyle: .body)
        descriptionView.textColor = .label
        descriptionView.backgroundColor = .clear
        descriptionView.isScrollEnabled = false
        descriptionView.textContainerInset = .zero
        descriptionView.textContainer.lineFragmentPadding = 0
        descriptionView.delegate = self

        descriptionPlaceholder.text = "Описание"
        descriptionPlaceholder.font = descriptionView.font
        descriptionPlaceholder.textColor = .placeholderText
        descriptionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        descriptionView.addSubview(descriptionPlaceholder)
        NSLayoutConstraint.activate([
            descriptionPlaceholder.topAnchor.constraint(equalTo: descriptionView.topAnchor),
            descriptionPlaceholder.leadingAnchor.constraint(equalTo: descriptionView.leadingAnchor)
        ])
    }

    private func makeHeaderGroup() -> UIView {
        titleView.text = task.title
        titlePlaceholder.isHidden = !task.title.isEmpty
        descriptionView.text = task.subtitle
        descriptionPlaceholder.isHidden = !task.subtitle.isEmpty
        let titleRow = Self.paddedRow(titleView, minHeight: 52, vertical: 14)
        let descriptionRow = Self.paddedRow(descriptionView, minHeight: 52, vertical: 14)
        return GroupView(rows: [titleRow, descriptionRow])
    }


    // MARK: - Настройки задачи

    /// Блоки «Детали задачи» и «Люди» — каждый с маленькой подписью сверху
    private func makeSettingsGroup() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            Self.caption("Детали задачи"),
            GroupView(rows: [dueDateRow(), boardRow(), columnRow(), tagsRow()], separatorLeading: ListRowMetrics.textLeading),
            Self.caption("Люди"),
            GroupView(rows: [authorRow(), assigneeRow()], separatorLeading: ListRowMetrics.textLeading)
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[1])
        return stack
    }

    static var captionFont: UIFont { .sectionHeader }

    static func caption(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = captionFont
        label.textColor = .secondaryLabel
        return inset(label, leading: 16)
    }

    private func boardRow() -> UIView {
        let actions = boards.map { item in
            UIAction(
                title: item.title,
                image: BoardIcon.image(for: item, size: 24),
                state: item.id == board.id ? .on : .off
            ) { [weak self] _ in
                guard let self, item.id != self.board.id else { return }
                self.onMoveToBoard?(item.id)
            }
        }
        // Слева — цветная иконка самой доски, справа — только название
        let value = Self.popupButton(
            title: board.title,
            menu: UIMenu(options: .singleSelection, children: actions)
        )
        return SettingRow(title: "Доска", image: BoardIcon.image(for: board, size: ListRowMetrics.boardIconSize), value: value)
    }

    private func columnRow() -> UIView {
        let current = board.task(withID: task.id)?.column
        let actions = board.columns.enumerated().map { index, column in
            UIAction(title: column.title, state: index == current ? .on : .off) { [weak self] _ in
                guard let self, index != current else { return }
                self.task.record("Перенёс(ла) в «\(column.title)»")
                self.commit()
                self.onMoveToColumn?(index)
            }
        }
        let title = current.map { board.columns[$0].title } ?? "Нет"
        return SettingRow(
            title: "Колонка",
            symbol: "align.vertical.top",
            value: Self.popupButton(title: title, menu: UIMenu(options: .singleSelection, children: actions))
        )
    }

    private func assigneeRow() -> UIView {
        let none = UIAction(title: "Нет", state: task.assignee == nil ? .on : .off) { [weak self] _ in
            self?.setAssignee(nil)
        }
        let people = TeamSample.people.map { person in
            UIAction(
                title: person.fullName,
                image: person.avatar(size: 24),
                state: person.id == task.assignee?.id ? .on : .off
            ) { [weak self] _ in self?.setAssignee(person) }
        }
        let menu = UIMenu(options: .singleSelection, children: [none, UIMenu(options: .displayInline, children: people)])
        // Аватар слева вместо значка; без исполнителя — значок-заглушка
        let value = Self.popupButton(title: task.assignee?.fullName ?? "Нет", menu: menu)
        return Self.personRow(title: "Исполнитель", person: task.assignee, value: value)
    }

    private func setAssignee(_ person: Person?) {
        task.assignee = person
        task.record(person.map { "Назначил(а) исполнителя: \($0.fullName)" } ?? "Снял(а) исполнителя")
        commit()
        replace(&settingsGroup, with: makeSettingsGroup())
    }

    private func dueDateRow() -> UIView {
        guard let date = task.dueDate else {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            func preset(_ title: String, _ symbol: String, days: Int) -> UIAction {
                UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                    self?.setDueDate(calendar.date(byAdding: .day, value: days, to: today))
                }
            }
            let menu = UIMenu(children: [
                preset("Сегодня", "calendar", days: 0),
                preset("Завтра", "sunrise", days: 1),
                preset("Через неделю", "calendar.badge.clock", days: 7),
                UIAction(title: "Выбрать дату…", image: UIImage(systemName: "calendar.badge.plus")) { [weak self] _ in
                    self?.setDueDate(today)
                }
            ])
            return SettingRow(title: "Срок", symbol: "calendar", value: Self.popupButton(title: "Нет", menu: menu))
        }
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        picker.locale = Locale(identifier: "ru_RU")
        picker.date = date
        picker.addAction(UIAction { [weak self, weak picker] _ in
            guard let picker else { return }
            self?.task.dueDate = picker.date
            self?.task.record("Изменил(а) срок")
            self?.commit()
        }, for: .valueChanged)
        // Убрать срок — долгим нажатием на строку
        let row = SettingRow(title: "Срок", symbol: "calendar", value: picker)
        row.contextActions = [
            UIAction(title: "Убрать срок", image: UIImage(systemName: "calendar.badge.minus"), attributes: .destructive) { [weak self] _ in
                self?.setDueDate(nil)
            }
        ]
        return row
    }

    private func setDueDate(_ date: Date?) {
        task.dueDate = date
        task.record(date == nil ? "Убрал(а) срок" : "Установил(а) срок")
        commit()
        replace(&settingsGroup, with: makeSettingsGroup())
    }

    private func tagsRow() -> UIView {
        let value: UIView
        if task.tags.isEmpty {
            value = Self.popupLabel("Нет")
        } else {
            let chips = UIStackView(arrangedSubviews: task.tags.prefix(3).map { TagChip(tag: $0) })
            chips.spacing = 6
            if task.tags.count > 3 {
                let more = UILabel()
                more.text = "+\(task.tags.count - 3)"
                more.font = .preferredFont(forTextStyle: .subheadline)
                more.textColor = .secondaryLabel
                chips.addArrangedSubview(more)
            }
            value = chips
        }
        let row = SettingRow(title: "Теги", symbol: "number", value: value, showsDisclosure: true)
        row.onTap = { [weak self] in self?.openTagsEditor() }
        return row
    }

    private func openTagsEditor() {
        let editor = TaskTagsViewController(selected: task.tags)
        editor.onChange = { [weak self] tags in
            guard let self else { return }
            self.task.tags = tags
            self.commit()
            self.replace(&self.settingsGroup, with: self.makeSettingsGroup())
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func authorRow() -> UIView {
        let name = UILabel()
        name.text = task.author?.fullName ?? "Нет"
        name.font = .preferredFont(forTextStyle: .body)
        name.textColor = .secondaryLabel
        return Self.personRow(title: "Автор", person: task.author, value: name)
    }

    /// Строка «Люди»: слева аватар человека, а если его нет — серый значок
    private static func personRow(title: String, person: Person?, value: UIView) -> SettingRow {
        guard let person else { return SettingRow(title: title, symbol: "person", value: value) }
        return SettingRow(title: title, image: person.avatar(size: ListRowMetrics.iconSize), value: value)
    }

    // MARK: - Чек-лист

    private func makeChecklistGroup() -> UIView {
        let done = task.checklist.filter(\.isDone).count
        checklistProgress.text = task.checklist.isEmpty ? nil : "\(done) из \(task.checklist.count)"
        var rows: [UIView] = task.checklist.map { item in
            let row = ChecklistRow(item: item)
            row.onToggle = { [weak self] in self?.toggleChecklistItem(item.id) }
            row.onTitleChange = { [weak self] title in self?.renameChecklistItem(item.id, title) }
            row.onDelete = { [weak self] in self?.deleteChecklistItem(item.id) }
            row.onReturn = { [weak self] in self?.addChecklistItem() }
            return row
        }
        let add = AddRow(title: "Добавить пункт")
        add.onTap = { [weak self] in self?.addChecklistItem() }
        rows.append(add)
        return GroupView(rows: rows, separatorLeading: ListRowMetrics.textLeading)
    }

    private func rebuildChecklist(focusing id: String? = nil) {
        replace(&checklistGroup, with: makeChecklistGroup())
        commit()
        guard let id else { return }
        let row = (checklistGroup as? GroupView)?.rows.compactMap { $0 as? ChecklistRow }.first { $0.itemID == id }
        row?.focus()
    }

    private func toggleChecklistItem(_ id: String) {
        guard let index = task.checklist.firstIndex(where: { $0.id == id }) else { return }
        task.checklist[index].isDone.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        rebuildChecklist()
    }

    private func renameChecklistItem(_ id: String, _ title: String) {
        guard let index = task.checklist.firstIndex(where: { $0.id == id }) else { return }
        task.checklist[index].title = title
        checklistProgress.text = "\(task.checklist.filter(\.isDone).count) из \(task.checklist.count)"
        commit()
    }

    private func deleteChecklistItem(_ id: String) {
        task.checklist.removeAll { $0.id == id }
        rebuildChecklist()
    }

    private func addChecklistItem() {
        // Пустой последний пункт не плодим — просто фокусируемся на нём
        if let last = task.checklist.last, last.title.trimmingCharacters(in: .whitespaces).isEmpty {
            rebuildChecklist(focusing: last.id)
            return
        }
        let item = ChecklistItem(title: "")
        task.checklist.append(item)
        rebuildChecklist(focusing: item.id)
    }

    // MARK: - Комментарии · История · Файлы · Связи

    @objc private func segmentChanged() {
        replace(&activityGroup, with: makeActivityGroup())
    }

    private func makeActivityGroup() -> UIView {
        switch ActivityTab(rawValue: segment.selectedSegmentIndex) ?? .comments {
        case .comments:
            guard !task.comments.isEmpty else {
                return EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "Нет комментариев",
                                      message: "Напишите первый комментарий ниже")
            }
            return GroupView(rows: task.comments.map { CommentRow(comment: $0) }, separatorLeading: 60)
        case .history:
            guard !task.history.isEmpty else {
                return EmptyStateView(symbol: "clock.arrow.circlepath", title: "История пуста", message: nil)
            }
            return GroupView(rows: task.history.reversed().map { HistoryRow(event: $0) }, separatorLeading: 52)
        case .files:
            var rows: [UIView] = task.attachments.reversed().map { FileRow(attachment: $0) }
            let add = AddRow(title: "Добавить файл")
            add.onTap = { [weak self] in self?.pickAttachment(.file) }
            rows.append(add)
            return GroupView(rows: rows, separatorLeading: ListRowMetrics.textLeading)
        case .links:
            let linked = task.links.compactMap { id in boards.lazy.compactMap { $0.task(withID: id)?.task }.first }
            var rows: [UIView] = linked.map { other in
                let row = LinkRow(title: other.title)
                row.onDelete = { [weak self] in
                    self?.task.links.removeAll { $0 == other.id }
                    self?.commit()
                    self?.segmentChanged()
                }
                return row
            }
            let candidates = board.allTasks.filter { $0.id != task.id && !task.links.contains($0.id) }
            let add = AddRow(title: "Добавить связь")
            add.menu = UIMenu(title: "Связать с задачей", children: candidates.map { other in
                UIAction(title: other.title) { [weak self] _ in
                    self?.task.links.append(other.id)
                    self?.task.record("Связал(а) с «\(other.title)»")
                    self?.commit()
                    self?.segmentChanged()
                }
            })
            rows.append(add)
            return GroupView(rows: rows, separatorLeading: ListRowMetrics.textLeading)
        }
    }

    private func addComment(text: String, attachment: TaskAttachment?) {
        task.comments.append(TaskComment(author: TeamSample.me, text: text, attachment: attachment))
        if let attachment {
            task.attachments.append(attachment)
            task.record("Прикрепил(а) файл «\(attachment.name)»")
        }
        commit()
        segment.selectedSegmentIndex = ActivityTab.comments.rawValue
        segmentChanged()
        view.layoutIfNeeded()
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        if bottom > 0 { scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: true) }
    }

    // MARK: - Вложения

    enum AttachmentSource { case photo, file }

    private func pickAttachment(_ source: AttachmentSource) {
        switch source {
        case .photo:
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
        case .file:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    private func attachPicked(name: String) {
        // Из списка «Файлы» — сразу в задачу, из поля комментария — к комментарию
        if segment.selectedSegmentIndex == ActivityTab.files.rawValue && !composer.isEditingComment {
            let attachment = TaskAttachment(name: name)
            task.attachments.append(attachment)
            task.record("Прикрепил(а) файл «\(name)»")
            commit()
            segmentChanged()
        } else {
            composer.setAttachment(TaskAttachment(name: name))
        }
    }

    // MARK: - Общие элементы

    private static let createdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE, d MMMM"
        return formatter
    }()

    /// «Пн, 5 октября»
    private static func createdText(_ date: Date) -> String {
        let text = createdFormatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Единая высота всех «пузырей»: капсулы навбара, «Изменить», лупы, поле комментария, сегменты
    static let bubbleHeight: CGFloat = 44

    /// Значение с картинкой: картинка — отдельный view фиксированного размера. Внутри кнопки
    /// она сжималась вместе с текстом, и у квадратной иконки пропадало скругление справа
    static func popupValue(title: String, image: UIImage?, menu: UIMenu) -> UIView {
        let button = popupButton(title: title, menu: menu)
        guard let image else { return button }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: image.size.width),
            imageView.heightAnchor.constraint(equalToConstant: image.size.height)
        ])
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [imageView, button])
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }

    /// Кнопка-значение справа в строке настроек: «Значение ⌃⌄», по нажатию — меню
    static func popupButton(title: String, image: UIImage? = nil, menu: UIMenu) -> UIButton {
        var config = UIButton.Configuration.plain()
        var attributed = AttributedString(title)
        attributed.font = .preferredFont(forTextStyle: .body)
        config.attributedTitle = attributed
        config.image = image
        config.imagePadding = 8
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = .zero
        config.indicator = .popup
        config.titleLineBreakMode = .byTruncatingTail
        let button = UIButton(configuration: config)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.titleLabel?.numberOfLines = 1
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    /// То же оформление «Нет ⌃⌄», но без собственного меню — строка открывает экран
    static func popupLabel(_ title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        let chevrons = UIImageView(image: UIImage(
            systemName: "chevron.up.chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ))
        chevrons.tintColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, chevrons])
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }

    static func paddedRow(_ content: UIView, minHeight: CGFloat, vertical: CGFloat = 0) -> UIView {
        let row = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
            content.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            content.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -vertical),
            content.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    static func inset(_ view: UIView, leading: CGFloat = 0, trailing: CGFloat = 0) -> UIView {
        let wrapper = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -trailing)
        ])
        return wrapper
    }
}

extension TaskDetailViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Return в названии переводит к описанию, а не вставляет перенос
        guard textView === titleView, text == "\n" else { return true }
        descriptionView.becomeFirstResponder()
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        if textView === titleView {
            titlePlaceholder.isHidden = !textView.text.isEmpty
            task.title = textView.text
        } else {
            descriptionPlaceholder.isHidden = !textView.text.isEmpty
            task.subtitle = textView.text
        }
        commit()
    }
}

extension TaskDetailViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        let name = result.itemProvider.suggestedName.map { "\($0).jpg" } ?? "Фото.jpg"
        attachPicked(name: name)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        attachPicked(name: url.lastPathComponent)
    }
}

// MARK: - Белая группа со скруглением и разделителями, как inset grouped список

final class GroupView: UIView {
    let rows: [UIView]

    /// Разделитель как в нативных списках iOS 26: начинается у текста строки, справа отступ 16 pt
    init(rows: [UIView], separatorLeading: CGFloat = 16) {
        self.rows = rows
        super.init(frame: .zero)
        backgroundColor = .detailGroup
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            guard index < rows.count - 1 else { continue }
            let separator = UIView()
            separator.backgroundColor = .separator
            let wrapper = TaskDetailViewController.inset(separator, leading: separatorLeading, trailing: 16)
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            stack.addArrangedSubview(wrapper)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Строка настроек: иконка и заголовок слева, значение справа
final class SettingRow: UIView, UIContextMenuInteractionDelegate {
    var onTap: (() -> Void)? {
        didSet { isUserInteractionEnabled = true }
    }

    /// Действия по долгому нажатию на строку
    var contextActions: [UIAction] = [] {
        didSet {
            guard !contextActions.isEmpty, interactions.isEmpty else { return }
            addInteraction(UIContextMenuInteraction(delegate: self))
        }
    }

    convenience init(title: String, symbol: String, value: UIView, showsDisclosure: Bool = false) {
        let image = UIImage(systemName: symbol, withConfiguration: ListRowMetrics.symbolConfiguration)
        self.init(title: title, image: image, value: value, showsDisclosure: showsDisclosure)
    }

    /// Вместо серого символа слева — готовая картинка (например, цветная иконка доски)
    init(title: String, image: UIImage?, value: UIView, showsDisclosure: Bool = false) {
        super.init(frame: .zero)
        let icon = UIImageView(image: image)
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        // Картинки (аватар, иконка доски) — в своём собственном размере, SF-символы — в своём кегле
        if let image, !image.isSymbolImage {
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: image.size.width),
                icon.heightAnchor.constraint(equalToConstant: image.size.height)
            ])
        }
        let iconSlot = ListRowMetrics.slot(icon)

        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        var views: [UIView] = [iconSlot, label, UIView(), value]
        if showsDisclosure {
            let chevrons = UIImageView(image: UIImage(
                systemName: "chevron.up.chevron.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            ))
            chevrons.tintColor = .secondaryLabel
            if !(value is UIStackView && (value as! UIStackView).arrangedSubviews.last is UIImageView) {
                views.append(chevrons)
            }
        }
        let stack = UIStackView(arrangedSubviews: views)
        stack.spacing = 8
        stack.setCustomSpacing(ListRowMetrics.gap, after: iconSlot)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListRowMetrics.leading),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onTap?()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        let actions = contextActions
        return UIContextMenuConfiguration(actionProvider: { _ in UIMenu(children: actions) })
    }
}

/// Общая сетка строк с иконкой слева: иконка по центру слота фиксированной ширины,
/// текст всегда с одной вертикали — у пунктов чек-листа, «Добавить …», файлов и связей
enum ListRowMetrics {
    static let leading: CGFloat = 14
    static let iconSlot: CGFloat = 28
    static let gap: CGFloat = 12
    /// Единый размер всего, что стоит слева: иконки доски, аватары, радио, «+», значки настроек
    static let iconSize: CGFloat = ListIconStyle.plateSize
    /// Где начинается текст строки — от этой вертикали идут разделители
    static var textLeading: CGFloat { leading + iconSlot + gap }

    /// Конфигурация SF-символов слева: при этом кегле круг радио ≈ 24 pt, как аватар и иконка доски
    static let symbolConfiguration = ListIconStyle.lineSymbolConfiguration
    /// Кегль чекбокса чек-листа: круг ≈ 28 pt, как аватар
    static let checkboxConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: UIImage.appSymbolWeight)
    /// Иконка доски в карточке задачи — чуть меньше аватара
    static let boardIconSize: CGFloat = 24

    /// Иконка в слоте, отцентрованная по его ширине
    static func slot(_ view: UIView) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: iconSlot),
            container.heightAnchor.constraint(equalToConstant: iconSlot),
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        container.setContentHuggingPriority(.required, for: .horizontal)
        container.setContentCompressionResistancePriority(.required, for: .horizontal)
        return container
    }
}

/// Строка «+ Добавить …» зелёным
final class AddRow: UIView {
    var onTap: (() -> Void)?
    var menu: UIMenu? {
        didSet {
            button.menu = menu
            button.showsMenuAsPrimaryAction = menu != nil
        }
    }

    /// Прозрачная кнопка на всю строку: нажатие и меню
    private let button = UIButton(type: .system)

    init(title: String) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(
            systemName: "plus",
            withConfiguration: ListRowMetrics.symbolConfiguration
        ))
        icon.tintColor = DetailTheme.accent
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = DetailTheme.accent
        let stack = UIStackView(arrangedSubviews: [ListRowMetrics.slot(icon), label])
        stack.spacing = ListRowMetrics.gap
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = title
        button.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListRowMetrics.leading),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Пункт чек-листа: кружок-отметка и редактируемый текст. Удаление — через контекстное меню
final class ChecklistRow: UIView, UITextViewDelegate, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
    let itemID: String
    /// Открытая свайпом строка — одновременно может быть открыта только одна
    private static weak var openRow: ChecklistRow?
    private static let actionWidth: CGFloat = 88

    private let content = UIView()
    private let deleteButton = UIButton(type: .system)
    private var offset: CGFloat = 0
    private var deleteWidth: NSLayoutConstraint!
    var onToggle: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?

    /// Многострочное поле: длинный пункт переносится и растит строку, а не обрезается «…»
    private let field = UITextView()
    private let placeholder = UILabel()

    init(item: ChecklistItem) {
        itemID = item.id
        super.init(frame: .zero)
        let check = UIButton(type: .system)
        let symbol = item.isDone ? "checkmark.circle.fill" : "circle"
        check.setImage(UIImage(systemName: symbol,
                               withConfiguration: ListRowMetrics.checkboxConfiguration), for: .normal)
        check.tintColor = item.isDone ? DetailTheme.accent : .tertiaryLabel
        check.accessibilityLabel = item.isDone ? "Снять отметку" : "Отметить выполненным"
        check.addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .touchUpInside)
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.setContentCompressionResistancePriority(.required, for: .horizontal)

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        field.text = item.title
        field.font = bodyFont
        field.isScrollEnabled = false
        field.backgroundColor = .clear
        field.textContainer.lineFragmentPadding = 0
        // Первая строка по центру радио (слот 28 pt)
        let firstLineInset = max(0, (ListRowMetrics.iconSlot - bodyFont.lineHeight) / 2)
        field.textContainerInset = UIEdgeInsets(top: firstLineInset, left: 0, bottom: firstLineInset, right: 0)
        field.returnKeyType = .next
        field.delegate = self
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        placeholder.text = "Новый пункт"
        placeholder.font = bodyFont
        placeholder.textColor = .placeholderText
        placeholder.isHidden = !item.title.isEmpty
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            placeholder.topAnchor.constraint(equalTo: field.topAnchor, constant: firstLineInset)
        ])
        if item.isDone {
            field.textColor = .secondaryLabel
            field.attributedText = NSAttributedString(
                string: item.title,
                attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: UIColor.secondaryLabel,
                             .font: UIFont.preferredFont(forTextStyle: .body)]
            )
        }
        let stack = UIStackView(arrangedSubviews: [ListRowMetrics.slot(check), field])
        stack.spacing = ListRowMetrics.gap
        // Радио в левом верхнем углу, текст растёт вниз
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Под строкой — красная кнопка «Удалить», строка уезжает влево свайпом, как в списках iPadOS
        clipsToBounds = true
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "trash.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.appSymbolWeight))
        config.imagePlacement = .top
        config.imagePadding = 4
        var title = AttributedString("Удалить")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        config.attributedTitle = title
        config.baseForegroundColor = .white
        deleteButton.configuration = config
        deleteButton.backgroundColor = .systemRed
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteWidth = deleteButton.widthAnchor.constraint(equalToConstant: Self.actionWidth)
        deleteButton.addAction(UIAction { [weak self] _ in self?.performDelete() }, for: .touchUpInside)
        addSubview(deleteButton)

        content.backgroundColor = .detailGroup
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: ListRowMetrics.leading),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            deleteButton.topAnchor.constraint(equalTo: topAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            deleteWidth
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeIfOpen))
        tap.delegate = self
        content.addGestureRecognizer(tap)
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    // MARK: Свайп «Удалить»

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if let pan = gesture as? UIPanGestureRecognizer, pan.view === self {
            // Только горизонтальный свайп — вертикальный остаётся прокрутке
            var direction = pan.velocity(in: self)
            if direction == .zero { direction = pan.translation(in: self) }
            return abs(direction.x) > abs(direction.y)
        }
        return super.gestureRecognizerShouldBegin(gesture)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Нажатие по строке только закрывает открытую кнопку, иначе строка работает как обычно
        gesture is UITapGestureRecognizer ? offset != 0 : true
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            if Self.openRow !== self { Self.openRow?.close() }
            endEditing(true)
        case .changed:
            let raw = (offset == 0 ? 0 : -Self.actionWidth) + pan.translation(in: self).x
            // Влево тянется свободно, вправо — с сопротивлением
            setOffset(raw > 0 ? raw * 0.2 : raw)
        case .ended, .cancelled:
            let x = content.transform.tx
            let velocity = pan.velocity(in: self).x
            if x < -bounds.width * 0.6 || (velocity < -1500 && x < -Self.actionWidth) {
                performDelete()
            } else if x < -Self.actionWidth / 2 || velocity < -400 {
                open()
            } else {
                close()
            }
        default:
            break
        }
    }

    private func setOffset(_ x: CGFloat) {
        content.transform = CGAffineTransform(translationX: x, y: 0)
        // Кнопка лежит под строкой у правого края и растягивается вслед за ней, как в системных списках
        deleteWidth.constant = max(Self.actionWidth, -x)
        layoutIfNeeded()
    }

    private func animate(to x: CGFloat) {
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.setOffset(x)
        }
    }

    private func open() {
        offset = -Self.actionWidth
        Self.openRow = self
        animate(to: offset)
    }

    func close() {
        offset = 0
        if Self.openRow === self { Self.openRow = nil }
        animate(to: 0)
    }

    @objc private func closeIfOpen() {
        close()
    }

    private func performDelete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.2) {
            self.setOffset(-self.bounds.width)
        } completion: { _ in
            self.onDelete?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus() {
        field.becomeFirstResponder()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Return — следующий пункт, а не перенос строки
        guard text == "\n" else { return true }
        onReturn?()
        return false
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        onTitleChange?(textView.text)
        // Строка растёт вместе с текстом
        invalidateIntrinsicContentSize()
        UIView.performWithoutAnimation { self.window?.layoutIfNeeded() }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // Пустой пункт после редактирования убираем
        if textView.text.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.async { [weak self] in self?.onDelete?() }
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Удалить", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.onDelete?()
                }
            ])
        })
    }
}

/// Аватар и имя человека
final class PersonLabel: UIStackView {
    init(person: Person) {
        let avatar = UIImageView(image: person.avatar(size: 24))
        let name = UILabel()
        name.text = person.fullName
        name.font = .preferredFont(forTextStyle: .body)
        name.textColor = .secondaryLabel
        name.lineBreakMode = .byTruncatingTail
        super.init(frame: .zero)
        addArrangedSubview(avatar)
        addArrangedSubview(name)
        spacing = 8
        alignment = .center
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Цветная капсула тега
final class TagChip: UILabel {
    private let insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    init(tag: TaskTag) {
        super.init(frame: .zero)
        text = tag.title
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = tag.color
        backgroundColor = tag.color.withAlphaComponent(0.14)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

final class EmptyStateView: UIView {
    init(symbol: String, title: String, message: String?) {
        super.init(frame: .zero)
        backgroundColor = .clear
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol,
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)))
        icon.tintColor = .tertiaryLabel
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.isHidden = message == nil
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, messageLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private let activityTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM, HH:mm"
    return formatter
}()

final class CommentRow: UIView {
    init(comment: TaskComment) {
        super.init(frame: .zero)
        let avatar = UIImageView(image: comment.author.avatar(size: 32))
        avatar.setContentHuggingPriority(.required, for: .horizontal)
        let name = UILabel()
        name.text = comment.author.fullName
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        let time = UILabel()
        time.text = activityTimeFormatter.string(from: comment.date)
        time.font = .preferredFont(forTextStyle: .footnote)
        time.textColor = .secondaryLabel
        let header = UIStackView(arrangedSubviews: [name, time, UIView()])
        header.spacing = 8
        header.alignment = .firstBaseline
        let text = UILabel()
        text.text = comment.text
        text.font = .preferredFont(forTextStyle: .body)
        text.numberOfLines = 0
        text.isHidden = comment.text.isEmpty
        let body = UIStackView(arrangedSubviews: [header, text])
        body.axis = .vertical
        body.spacing = 4
        if let attachment = comment.attachment {
            body.addArrangedSubview(AttachmentChip(name: attachment.name))
        }
        let stack = UIStackView(arrangedSubviews: [avatar, body])
        stack.spacing = 12
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class HistoryRow: UIView {
    init(event: TaskHistoryEvent) {
        super.init(frame: .zero)
        let avatar = UIImageView(image: event.author.avatar(size: 24))
        avatar.setContentHuggingPriority(.required, for: .horizontal)
        let text = UILabel()
        let attributed = NSMutableAttributedString(
            string: event.author.fullName + " ",
            attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]
        )
        attributed.append(NSAttributedString(string: event.text.lowercasedFirst,
                                             attributes: [.font: UIFont.systemFont(ofSize: 15)]))
        text.attributedText = attributed
        text.numberOfLines = 0
        let time = UILabel()
        time.text = activityTimeFormatter.string(from: event.date)
        time.font = .preferredFont(forTextStyle: .footnote)
        time.textColor = .secondaryLabel
        let body = UIStackView(arrangedSubviews: [text, time])
        body.axis = .vertical
        body.spacing = 2
        let stack = UIStackView(arrangedSubviews: [avatar, body])
        stack.spacing = 12
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FileRow: UIView {
    init(attachment: TaskAttachment) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: FileRow.symbol(for: attachment.name),
                                              withConfiguration: ListRowMetrics.symbolConfiguration))
        icon.tintColor = DetailTheme.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = UILabel()
        name.text = attachment.name
        name.font = .preferredFont(forTextStyle: .body)
        name.lineBreakMode = .byTruncatingMiddle
        let date = UILabel()
        date.text = activityTimeFormatter.string(from: attachment.date)
        date.font = .preferredFont(forTextStyle: .footnote)
        date.textColor = .secondaryLabel
        let body = UIStackView(arrangedSubviews: [name, date])
        body.axis = .vertical
        let stack = UIStackView(arrangedSubviews: [ListRowMetrics.slot(icon), body])
        stack.spacing = ListRowMetrics.gap
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListRowMetrics.leading),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func symbol(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif": return "photo"
        case "pdf": return "doc.richtext"
        case "zip": return "doc.zipper"
        default: return "doc"
        }
    }
}

final class LinkRow: UIView {
    var onDelete: (() -> Void)?

    init(title: String) {
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: "link", withConfiguration: ListRowMetrics.symbolConfiguration))
        icon.tintColor = DetailTheme.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 2
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        remove.tintColor = .tertiaryLabel
        remove.accessibilityLabel = "Убрать связь"
        remove.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        remove.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [ListRowMetrics.slot(icon), label, remove])
        stack.spacing = ListRowMetrics.gap
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ListRowMetrics.leading),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AttachmentChip: UIView {
    var onRemove: (() -> Void)? {
        didSet { removeButton.isHidden = onRemove == nil }
    }

    private let removeButton = UIButton(type: .system)

    init(name: String) {
        super.init(frame: .zero)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: FileRow.symbol(for: name)))
        icon.tintColor = DetailTheme.accent
        let label = UILabel()
        label.text = name
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.lineBreakMode = .byTruncatingMiddle
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .secondaryLabel
        removeButton.isHidden = true
        removeButton.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [icon, label, removeButton])
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Поле комментария, как в «Сообщениях»: «+» слева, капсула с полем и кнопкой отправки

final class CommentComposerView: UIView, UITextViewDelegate {
    var onSend: ((String, TaskAttachment?) -> Void)?
    var onAttach: ((TaskDetailViewController.AttachmentSource) -> Void)?
    var isEditingComment: Bool { textView.isFirstResponder }

    private let plusButton = UIButton(type: .system)
    private let capsule = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let sendButton = UIButton(type: .system)
    private let attachmentHolder = UIStackView()
    private var textHeight: NSLayoutConstraint!
    private var attachment: TaskAttachment?

    override init(frame: CGRect) {
        super.init(frame: frame)

        var plusConfig = UIButton.Configuration.glass()
        plusConfig.image = UIImage(systemName: "plus",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.appSymbolWeight))
        plusConfig.image = plusConfig.image?.withTintColor(DetailTheme.accent, renderingMode: .alwaysOriginal)
        plusConfig.baseForegroundColor = DetailTheme.accent
        plusConfig.cornerStyle = .capsule
        plusButton.configuration = plusConfig
        plusButton.accessibilityLabel = "Прикрепить"
        plusButton.showsMenuAsPrimaryAction = true
        plusButton.menu = UIMenu(children: [
            UIAction(title: "Фото", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
                self?.onAttach?(.photo)
            },
            UIAction(title: "Файл", image: UIImage(systemName: "doc")) { [weak self] _ in
                self?.onAttach?(.file)
            }
        ])
        plusButton.translatesAutoresizingMaskIntoConstraints = false

        capsule.cornerConfiguration = .capsule(maximumRadius: TaskDetailViewController.bubbleHeight / 2)
        capsule.translatesAutoresizingMaskIntoConstraints = false

        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholder.text = "Комментарий"
        placeholder.font = textView.font
        placeholder.textColor = .placeholderText
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)), for: .normal)
        sendButton.tintColor = DetailTheme.accent
        sendButton.accessibilityLabel = "Отправить"
        sendButton.isHidden = true
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        attachmentHolder.axis = .horizontal
        attachmentHolder.translatesAutoresizingMaskIntoConstraints = false

        addSubview(attachmentHolder)
        addSubview(plusButton)
        addSubview(capsule)
        capsule.contentView.addSubview(textView)
        capsule.contentView.addSubview(placeholder)
        capsule.contentView.addSubview(sendButton)

        textHeight = textView.heightAnchor.constraint(equalToConstant: TaskDetailViewController.bubbleHeight)
        NSLayoutConstraint.activate([
            attachmentHolder.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            attachmentHolder.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            attachmentHolder.trailingAnchor.constraint(lessThanOrEqualTo: capsule.trailingAnchor),

            capsule.topAnchor.constraint(equalTo: attachmentHolder.bottomAnchor, constant: 8),
            capsule.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 10),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            plusButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            plusButton.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: TaskDetailViewController.bubbleHeight),
            plusButton.heightAnchor.constraint(equalToConstant: TaskDetailViewController.bubbleHeight),

            textView.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            textHeight,

            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholder.centerYAnchor.constraint(equalTo: capsule.contentView.centerYAnchor),

            sendButton.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -6),
            sendButton.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 28),
            sendButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttachment(_ attachment: TaskAttachment?) {
        self.attachment = attachment
        attachmentHolder.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let attachment {
            let chip = AttachmentChip(name: attachment.name)
            chip.onRemove = { [weak self] in self?.setAttachment(nil) }
            attachmentHolder.addArrangedSubview(chip)
        }
        updateState()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateState()
    }

    private func updateState() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        placeholder.isHidden = !textView.text.isEmpty
        sendButton.isHidden = trimmed.isEmpty && attachment == nil
        // Поле растёт до ~5 строк, дальше прокручивается
        let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        let height = min(max(TaskDetailViewController.bubbleHeight, fitting), 130)
        textView.isScrollEnabled = fitting > 130
        if abs(textHeight.constant - height) > 0.5 {
            textHeight.constant = height
            superview?.layoutIfNeeded()
        }
    }

    private func send() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachment != nil else { return }
        onSend?(text, attachment)
        textView.text = ""
        setAttachment(nil)
    }
}

// MARK: - Вкладки как в Safari

/// Полоса вкладок в стиле Safari: серая дорожка, выбранная вкладка — белая капсула с лёгкой тенью,
/// между невыбранными — тонкие разделители
final class TabStripControl: UIControl {
    var selectedSegmentIndex: Int = -1 {
        didSet { updateSelection(animated: oldValue >= 0 && window != nil) }
    }

    private let items: [(title: String, symbol: String)]
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let pill = UIView()
    private var tabs: [UIStackView] = []
    private var labels: [UILabel] = []
    private var icons: [UIImageView] = []
    private var dividers: [UIView] = []
    private static let inset: CGFloat = 4

    init(items: [(title: String, symbol: String)]) {
        self.items = items
        super.init(frame: .zero)
        // Дорожка — Liquid Glass, выбранная вкладка — серая капсула (как переключатель вида в «Файлах»)
        glass.cornerConfiguration = .capsule()
        glass.isUserInteractionEnabled = false
        addSubview(glass)

        pill.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.14) : UIColor(white: 0, alpha: 0.07)
        }
        pill.isUserInteractionEnabled = false
        addSubview(pill)

        for (index, item) in items.enumerated() {
            let icon = UIImageView(image: UIImage(
                systemName: item.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: UIImage.appSymbolWeight)
            ))
            icon.contentMode = .center
            let label = UILabel()
            label.text = item.title
            label.font = .preferredFont(forTextStyle: .subheadline)
            // Вкладки только с текстом
            icon.isHidden = true
            let tab = UIStackView(arrangedSubviews: [icon, label])
            tab.spacing = 6
            tab.alignment = .center
            tab.isUserInteractionEnabled = false
            tab.isAccessibilityElement = true
            tab.accessibilityLabel = item.title
            tab.accessibilityTraits = .button
            addSubview(tab)
            tabs.append(tab)
            labels.append(label)
            icons.append(icon)
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.isUserInteractionEnabled = false
                addSubview(divider)
                dividers.append(divider)
            }
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Рамки вкладок: у каждой ширина по её тексту, свободное место делится поровну
    private var segmentFrames: [CGRect] = []
    private static let textPadding: CGFloat = 16

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let textWidths = labels.map { ceil($0.intrinsicContentSize.width) }
        let natural = textWidths.reduce(0) { $0 + $1 + Self.textPadding * 2 }
        let extra = max(0, bounds.width - Self.inset * 2 - natural) / CGFloat(max(items.count, 1))
        var x = Self.inset
        segmentFrames = textWidths.map { textWidth in
            let width = textWidth + Self.textPadding * 2 + extra
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: bounds.height)
        }
        for (index, tab) in tabs.enumerated() {
            let size = tab.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let frame = segmentFrames[index]
            tab.frame = CGRect(x: frame.midX - size.width / 2, y: (bounds.height - size.height) / 2,
                               width: size.width, height: size.height)
        }
        let dividerHeight = bounds.height * 0.42
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: segmentFrames[index + 1].minX - 0.5, y: (bounds.height - dividerHeight) / 2,
                                   width: 1 / UIScreen.main.scale, height: dividerHeight)
        }
        layoutPill()
        updateDividers()
    }

    /// Капсула выбранной вкладки занимает всю вкладку: у крайних — вплотную к краю дорожки
    private func layoutPill() {
        guard segmentFrames.indices.contains(selectedSegmentIndex) else { return }
        pill.frame = segmentFrames[selectedSegmentIndex].insetBy(dx: 0, dy: Self.inset)
        pill.layer.cornerRadius = pill.bounds.height / 2
    }

    /// Разделители у выбранной вкладки прячутся, как в Safari
    private func updateDividers() {
        for (index, divider) in dividers.enumerated() {
            let left = index, right = index + 1
            divider.alpha = (left == selectedSegmentIndex || right == selectedSegmentIndex) ? 0 : 1
        }
    }

    private func updateSelection(animated: Bool) {
        for (index, label) in labels.enumerated() {
            let selected = index == selectedSegmentIndex
            label.textColor = selected ? .label : .secondaryLabel
            // Размер как у заголовков секций, вес легче: выбранная вкладка — medium, остальные — regular
            label.font = .systemFont(ofSize: UIFont.sectionHeader.pointSize, weight: selected ? .medium : .regular)
            icons[index].tintColor = selected ? DetailTheme.accent : .secondaryLabel
            tabs[index].accessibilityTraits = selected ? [.button, .selected] : .button
        }
        // Ширина вкладок зависит от веса шрифта выбранной — перекладываем целиком
        setNeedsLayout()
        let changes = {
            self.layoutIfNeeded()
            self.layoutPill()
            self.updateDividers()
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        guard let index = segmentFrames.firstIndex(where: { x < $0.maxX }) ?? segmentFrames.indices.last,
              index != selectedSegmentIndex
        else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        selectedSegmentIndex = index
        sendActions(for: .valueChanged)
    }
}

// MARK: - Цвета инспектора

extension UIColor {
    /// Серый фон под плашками. Задан явно: в колонке-инспекторе уровень интерфейса «приподнятый»,
    /// и системные grouped-цвета меняются местами (фон белеет, плашки сереют)
    static let detailBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .black
            : UIColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1)
    }

    /// Белая плашка
    static let detailGroup = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            : .white
    }
}

// MARK: - Аватар и иконка доски

extension Person {
    /// Круглый аватар с инициалами на цветном градиенте
    func avatar(size: CGFloat) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            let colors = [color.withAlphaComponent(0.75).cgColor, color.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            UIBezierPath(ovalIn: rect).addClip()
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            let text = initials as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.4, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

enum BoardIcon {
    /// Квадратная иконка доски со скруглением, как у плашек в сайдбаре
    static func image(for board: Board, size: CGFloat) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            UIBezierPath(roundedRect: rect, cornerRadius: size * GradientIconPlate.cornerRatio).addClip()
            let colors = [board.iconTop.cgColor, board.iconBottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            if let emoji = board.emoji, !emoji.isEmpty {
                let text = emoji as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 0.6)]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
                return
            }
            let base: UIImage? = board.symbolName == "columns-3"
                ? UIImage(named: "columns-3")
                : UIImage(systemName: board.symbolName,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: UIImage.appSymbolWeight))
            guard let glyph = base?.withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            // Символ занимает ту же долю плашки, что и в сайдбаре
            let box = size * ListIconStyle.glyphRatio
            let scale = min(box / glyph.size.width, box / glyph.size.height)
            let drawSize = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
