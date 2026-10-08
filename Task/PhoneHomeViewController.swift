import UIKit

/// Главный экран на iPhone: плитки как в «Напоминаниях», доски списком как в «Настройках»,
/// «Изменить» в навбаре и круглая зелёная «+» в правом нижнем углу.
/// На iPad вместо него работает сайдбар (SidebarViewController).
final class PhoneHomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var boards: () -> [Board] = { [] }
    var smartCards: () -> [SidebarSmartCard] = { [] }
    var onSelectBoard: ((Board) -> Void)?
    var onDeleteBoard: ((String) -> Void)?
    var onMoveBoard: ((Int, Int) -> Void)?
    var onToggleSmartCard: ((String, Bool) -> Void)?
    var onMoveSmartCard: ((Int, Int) -> Void)?
    var onClose: (() -> Void)?
    var makeAddMenu: (() -> UIMenu)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let addButton = UIButton(type: .system)
    private var items: [Board] = []
    private var cards: [SidebarSmartCard] = []

    /// В режиме «Изменить», как в «Напоминаниях»: плитки превращаются в список с отметками,
    /// доски получают удаление и перестановку
    private var isEditingLists: Bool { tableView.isEditing }
    private var boardsSection: Int { isEditingLists ? 1 : 0 }
    /// «Архив» — отдельной строкой в самом низу, как «Недавно удалённые» в «Заметках»;
    /// в режиме «Изменить» не показывается
    private var archiveSection: Int? { isEditingLists ? nil : 1 }

    /// Размеры сняты с нативных «Напоминаний» и «Настроек» iOS 27 на iPhone 18 Pro
    private enum Metrics {
        static let tileHeight: CGFloat = 80
        static let tileSpacing: CGFloat = 9
        static let rowHeight: CGFloat = 52
        static let boardIconSize: CGFloat = 28
        static let addButtonSize: CGFloat = 48
        static let addButtonInset: CGFloat = 28
        /// Отступ белых групп от краёв экрана, как в «Настройках»
        static let groupInset: CGFloat = 16
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.tintColor = .notesAccent
        navigationItem.largeTitleDisplayMode = .never

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGroupedBackground
        tableView.rowHeight = Metrics.rowHeight
        tableView.register(PhoneBoardCell.self, forCellReuseIdentifier: PhoneBoardCell.reuseID)
        tableView.register(PhoneSmartListCell.self, forCellReuseIdentifier: PhoneSmartListCell.reuseID)
        tableView.allowsSelectionDuringEditing = true
        tableView.contentInset.bottom = Metrics.addButtonSize + Metrics.addButtonInset
        tableView.preservesSuperviewLayoutMargins = false
        tableView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: Metrics.groupInset, bottom: 0, trailing: Metrics.groupInset
        )
        view.addSubview(tableView)

        configureAddButton()
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateEditItem()
        let close = UIBarButtonItem(
            image: UIImage.notesBarGlyph("xmark"),
            primaryAction: UIAction { [weak self] _ in self?.onClose?() }
        )
        close.accessibilityLabel = "Закрыть"
        navigationItem.leftBarButtonItem = close
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: animated)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTilesHeader()
    }

    func reload() {
        guard isViewLoaded else { return }
        items = boards()
        cards = smartCards()
        tableView.tableHeaderView = isEditingLists ? nil : makeTilesHeader()
        layoutTilesHeader()
        tableView.reloadData()
    }

    // MARK: - «Изменить»

    private func updateEditItem(editing: Bool? = nil) {
        let item: UIBarButtonItem
        if editing ?? tableView.isEditing {
            // «Готово» — круглая залитая кнопка с галочкой, как в «Напоминаниях»
            item = UIBarButtonItem(
                image: UIImage(systemName: "checkmark",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
                style: .prominent,
                target: self,
                action: #selector(toggleEditing)
            )
            item.accessibilityLabel = "Готово"
        } else {
            item = UIBarButtonItem(title: "Изменить", style: .plain, target: self, action: #selector(toggleEditing))
        }
        item.tintColor = .notesAccent
        // Поиск — в самом правом углу, как в «Напоминаниях»
        let search = UIBarButtonItem(image: UIImage.notesBarGlyph("magnifyingglass"), style: .plain, target: nil, action: nil)
        search.accessibilityLabel = "Поиск"
        search.tintColor = .notesAccent
        navigationItem.setRightBarButtonItems([search, item], animated: true)
    }

    /// Как в «Напоминаниях»: прежний экран чуть сжимается и гаснет, новый проявляется на его месте,
    /// мягко подъезжая снизу. Строки не перестраиваются по ходу анимации — поэтому без прыжков
    @objc private func toggleEditing() {
        let editing = !tableView.isEditing
        cards = smartCards()
        // Кнопка навбара меняется сразу, вместе с началом анимации
        updateEditItem(editing: editing)

        guard let snapshot = tableView.snapshotView(afterScreenUpdates: false) else {
            applyEditingState(editing)
            return
        }
        snapshot.frame = tableView.frame
        view.insertSubview(snapshot, aboveSubview: tableView)

        applyEditingState(editing)
        tableView.alpha = 0
        tableView.transform = CGAffineTransform(translationX: 0, y: 14)
        if !editing {
            addButton.isHidden = false
            addButton.alpha = 0
            addButton.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0) {
            snapshot.alpha = 0
            snapshot.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            self.tableView.alpha = 1
            self.tableView.transform = .identity
            self.addButton.alpha = editing ? 0 : 1
            self.addButton.transform = editing ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
        } completion: { _ in
            snapshot.removeFromSuperview()
            self.addButton.isHidden = editing
        }
    }

    private func applyEditingState(_ editing: Bool) {
        tableView.setEditing(editing, animated: false)
        tableView.tableHeaderView = editing ? nil : makeTilesHeader()
        layoutTilesHeader()
        tableView.reloadData()
        tableView.layoutIfNeeded()
    }

    // MARK: - Круглая «+» в правом нижнем углу

    private func configureAddButton() {
        var config = UIButton.Configuration.prominentGlass()
        config.image = UIImage(systemName: "plus",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: UIImage.appSymbolWeight))
        config.baseBackgroundColor = .notesAccent
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        addButton.configuration = config
        addButton.tintColor = .notesAccent
        addButton.accessibilityLabel = "Добавить"
        addButton.showsMenuAsPrimaryAction = true
        addButton.menu = makeAddMenu?()
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            addButton.heightAnchor.constraint(equalToConstant: Metrics.addButtonSize),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.addButtonInset),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Metrics.addButtonInset)
        ])
    }

    /// Меню берётся у сайдбара — тот же список действий, что и на iPad
    func refreshAddMenu() {
        addButton.menu = makeAddMenu?()
    }

    // MARK: - Плитки

    private func makeTilesHeader() -> UIView {
        let tiles = cards.filter(\.isVisible).map(PhoneTileView.init(card:))
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = Metrics.tileSpacing
        var index = 0
        while index < tiles.count {
            let row = UIStackView(arrangedSubviews: Array(tiles[index..<min(index + 2, tiles.count)]))
            row.axis = .horizontal
            row.spacing = Metrics.tileSpacing
            row.distribution = .fillEqually
            if row.arrangedSubviews.count == 1 { row.addArrangedSubview(UIView()) }
            row.heightAnchor.constraint(equalToConstant: Metrics.tileHeight).isActive = true
            grid.addArrangedSubview(row)
            index += 2
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        let header = UIView()
        header.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            // Отступ до заголовка «Доски», как от плиток до «Мои списки» в «Напоминаниях»
            grid.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -22)
        ])
        return header
    }

    /// Ширина шапки таблицы задаётся вручную, высота — по содержимому
    private func layoutTilesHeader() {
        guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
        // Поля как у групп таблицы, чтобы плитки стояли по краям белых блоков
        let inset = tableView.layoutMargins.left
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
        header.frame.size.width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        if abs(header.frame.height - height) > 0.5 {
            header.frame.size.height = height
            tableView.tableHeaderView = header
        }
    }

    // MARK: - Доски, как список в «Настройках»

    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == archiveSection { return 1 }
        return section == boardsSection ? items.count : cards.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == boardsSection else { return nil }
        let header = UITableViewHeaderFooterView()
        var content = UIListContentConfiguration.prominentInsetGroupedHeader()
        content.text = "Доски"
        header.contentConfiguration = content
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == archiveSection { return 24 }
        return section == boardsSection ? UITableView.automaticDimension : 12
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == archiveSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: PhoneBoardCell.reuseID, for: indexPath) as! PhoneBoardCell
            cell.applyArchive()
            return cell
        }
        if indexPath.section != boardsSection {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PhoneSmartListCell.reuseID, for: indexPath
            ) as! PhoneSmartListCell
            cell.apply(card: cards[indexPath.row])
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: PhoneBoardCell.reuseID, for: indexPath) as! PhoneBoardCell
        cell.apply(board: items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == archiveSection {
            // Экрана архива пока нет — строка только подсвечивается
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        if indexPath.section != boardsSection {
            // Отметка показывает/скрывает плитку
            tableView.deselectRow(at: indexPath, animated: true)
            cards[indexPath.row].isVisible.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
            onToggleSmartCard?(cards[indexPath.row].id, cards[indexPath.row].isVisible)
            (tableView.cellForRow(at: indexPath) as? PhoneSmartListCell)?.apply(card: cards[indexPath.row])
            return
        }
        guard !isEditingLists else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        onSelectBoard?(items[indexPath.row])
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        indexPath.section == boardsSection ? .delete : .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == boardsSection
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        isEditingLists
    }

    /// Перестановка только внутри своего блока
    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt source: IndexPath,
        toProposedIndexPath proposed: IndexPath
    ) -> IndexPath {
        guard proposed.section != source.section else { return proposed }
        let row = proposed.section < source.section ? 0 : tableView.numberOfRows(inSection: source.section) - 1
        return IndexPath(row: row, section: source.section)
    }

    func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        if source.section == boardsSection {
            items.insert(items.remove(at: source.row), at: destination.row)
            onMoveBoard?(source.row, destination.row)
        } else {
            cards.insert(cards.remove(at: source.row), at: destination.row)
            onMoveSmartCard?(source.row, destination.row)
        }
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, indexPath.section == boardsSection else { return }
        let removed = items.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        onDeleteBoard?(removed.id)
    }
}

/// Смарт-список в режиме «Изменить», как в «Напоминаниях»: отметка, круглая цветная иконка, название
private final class PhoneSmartListCell: UITableViewCell {
    static let reuseID = "PhoneSmartList"
    private let check = UIImageView()
    private let iconPlate = UIImageView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        for view in [check, iconPlate, titleLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        titleLabel.font = .preferredFont(forTextStyle: .body)
        separatorInset = UIEdgeInsets(top: 0, left: 98, bottom: 0, right: 16)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            check.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconPlate.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            iconPlate.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 28),
            iconPlate.heightAnchor.constraint(equalToConstant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 98),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(card: SidebarSmartCard) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: UIImage.appSymbolWeight)
        check.image = UIImage(systemName: card.isVisible ? "checkmark.circle.fill" : "circle", withConfiguration: config)
        check.tintColor = card.isVisible ? .notesAccent : .tertiaryLabel
        iconPlate.image = Self.circleIcon(card: card, size: 28)
        titleLabel.text = card.editTitle
        accessibilityLabel = card.editTitle
        accessibilityValue = card.isVisible ? "Показывается" : "Скрыта"
    }

    private static func circleIcon(card: SidebarSmartCard, size: CGFloat) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        return UIGraphicsImageRenderer(size: rect.size).image { context in
            UIBezierPath(ovalIn: rect).addClip()
            let colors = [card.topColor.cgColor, card.bottomColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            if let glyph = UIImage(systemName: card.symbolName,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2))
            }
        }
    }
}

/// Строка доски как в «Настройках» iOS 27: иконка 28 pt в 14 pt от края группы, текст и разделитель с 56 pt.
/// Системная конфигурация ячейки ужимает картинки до ~22 pt, поэтому раскладка своя
private final class PhoneBoardCell: UITableViewCell {
    static let reuseID = "PhoneBoard"
    private static let iconSize: CGFloat = 28
    private static let iconLeading: CGFloat = 14
    private static let textLeading: CGFloat = 56

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        separatorInset = UIEdgeInsets(top: 0, left: Self.textLeading, bottom: 0, right: 16)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.iconLeading),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.textLeading),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyArchive() {
        let size = Self.iconSize
        iconView.image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            UIBezierPath(roundedRect: rect, cornerRadius: size * GradientIconPlate.cornerRatio).addClip()
            let colors = [UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1).cgColor,
                          UIColor(red: 99 / 255, green: 99 / 255, blue: 102 / 255, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            if let glyph = UIImage(systemName: "archivebox.fill",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2))
            }
        }
        titleLabel.text = "Архив"
    }

    func apply(board: Board) {
        iconView.image = BoardIcon.image(for: board, size: Self.iconSize)
        titleLabel.text = board.title
    }
}

/// Плитка смарт-списка как в «Напоминаниях» iOS 27: цветной градиент, белые иконка, счётчик и название
private final class PhoneTileView: UIView {
    private let gradient = CAGradientLayer()

    convenience init(card: SidebarSmartCard) {
        self.init(title: card.title, count: card.count, symbol: card.symbolName,
                  top: card.topColor, bottom: card.bottomColor)
    }

    init(title: String, count: String, symbol: String, top: UIColor, bottom: UIColor) {
        super.init(frame: .zero)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        gradient.colors = [top.cgColor, bottom.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)

        let icon = UIImageView(image: UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        ))
        icon.tintColor = .white
        let countLabel = UILabel()
        countLabel.text = count
        countLabel.textColor = .white
        countLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold).rounded
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        for view in [icon, countLabel, titleLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        ])
        isAccessibilityElement = true
        accessibilityLabel = count.isEmpty ? title : "\(title), \(count)"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

private extension UIFont {
    /// Скруглённый вариант шрифта, как у счётчиков в «Напоминаниях»
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
