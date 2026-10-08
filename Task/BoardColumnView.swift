import UIKit

final class BoardColumnView: UIView {
    private let headerTitleLabel = UILabel()
    private let countLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let cardsStack = UIStackView()
    private(set) var headerView = UIView()
    var onNewTask: ((UIButton) -> Void)?
    /// Долгое нажатие на заголовок — перенос колонки
    var onReorderGesture: ((UILongPressGestureRecognizer) -> Void)?
    /// Долгое нажатие на карточку — перенос задачи внутри колонки
    var onCardReorderGesture: ((UILongPressGestureRecognizer, UIView) -> Void)?
    /// Нажатие на карточку — открыть задачу
    var onCardTap: ((TaskCardView) -> Void)?

    var cardViews: [UIView] { cardsStack.arrangedSubviews }
    /// Стек карточек — сюда доска вставляет карточку, перенесённую из другой колонки
    var cardsStackView: UIStackView { cardsStack }

    /// Обновляет счётчик в заголовке по числу карточек, пока задачу переносят
    func refreshCount() {
        countLabel.text = "\(cardsStack.arrangedSubviews.count)"
    }

    /// Пока колонку несут в стопке, на её месте остаётся полупрозрачный заголовок-«слот»
    func setDragPlaceholder(_ isPlaceholder: Bool) {
        cardsStack.alpha = isPlaceholder ? 0 : 1
        headerView.alpha = isPlaceholder ? 0.35 : 1
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Выбор цвета в «⋯»: свой цвет или nil — «как у доски»
    var onChangeColor: ((UIColor?) -> Void)?

    func apply(column: BoardColumn, color: UIColor) {
        headerTitleLabel.text = column.title
        countLabel.text = "\(column.tasks.count)"
        headerTitleLabel.textColor = color
        countLabel.textColor = color.withAlphaComponent(0.6)
        addButton.tintColor = color
        plusButton.tintColor = color
        addButton.menu = makeMenu(customColor: column.customColor)
        cardsStack.arrangedSubviews.forEach { view in
            cardsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        column.tasks.forEach { task in
            let card = TaskCardView()
            card.apply(task: task)
            let reorder = UILongPressGestureRecognizer(target: self, action: #selector(cardReorderGesture(_:)))
            reorder.minimumPressDuration = 0.3
            card.addGestureRecognizer(reorder)
            let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
            tap.require(toFail: reorder)
            card.addGestureRecognizer(tap)
            cardsStack.addArrangedSubview(card)
        }
    }

    private func makeMenu(customColor: UIColor?) -> UIMenu {
        let boardColor = UIAction(
            title: "Цвет доски",
            image: UIImage(systemName: "rectangle.stack"),
            state: customColor == nil ? .on : .off
        ) { [weak self] _ in self?.onChangeColor?(nil) }
        let swatches = BoardColumn.palette.map { item in
            UIAction(
                title: item.title,
                image: UIImage(systemName: "circle.fill")?.withTintColor(item.color, renderingMode: .alwaysOriginal),
                state: customColor == item.color ? .on : .off
            ) { [weak self] _ in self?.onChangeColor?(item.color) }
        }
        let colorMenu = UIMenu(
            title: "Цвет",
            image: UIImage(systemName: "paintpalette"),
            options: .singleSelection,
            children: [boardColor, UIMenu(options: .displayInline, children: swatches)]
        )
        return UIMenu(children: [
            UIAction(
                title: "Редактировать",
                image: UIImage(systemName: "pencil")
            ) { _ in },
            colorMenu,
            UIAction(
                title: "Сортировать",
                image: UIImage(systemName: "arrow.up.arrow.down")
            ) { _ in },
            UIAction(
                title: "Удалить",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in }
        ])
    }

    private func configure() {
        backgroundColor = .clear
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        headerTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        headerTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        headerTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Та же толщина, что у иконок навбара
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: UIImage.appSymbolWeight)
        addButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: iconConfig), for: .normal)
        addButton.accessibilityLabel = "Ещё"
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        addButton.showsMenuAsPrimaryAction = true

        plusButton.setImage(UIImage(systemName: "plus", withConfiguration: iconConfig), for: .normal)
        plusButton.accessibilityLabel = "Новая задача"
        plusButton.setContentHuggingPriority(.required, for: .horizontal)
        plusButton.addTarget(self, action: #selector(headerPlusTapped), for: .touchUpInside)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [
            headerTitleLabel, countLabel, spacer, addButton, plusButton
        ])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 6
        header.setCustomSpacing(8, after: spacer)
        header.setCustomSpacing(20, after: addButton)
        // Заголовок и иконки выровнены по тексту внутри карточек
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: TaskCardView.contentInset,
            bottom: 0,
            trailing: TaskCardView.contentInset
        )
        headerView = header
        let reorder = UILongPressGestureRecognizer(target: self, action: #selector(reorderGesture(_:)))
        reorder.minimumPressDuration = 0.35
        header.addGestureRecognizer(reorder)

        cardsStack.axis = .vertical
        cardsStack.spacing = 10

        let content = UIStackView(arrangedSubviews: [header, cardsStack])
        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
        guard let card = gesture.view as? TaskCardView else { return }
        onCardTap?(card)
    }

    @objc private func cardReorderGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let card = gesture.view else { return }
        onCardReorderGesture?(gesture, card)
    }

    @objc private func reorderGesture(_ gesture: UILongPressGestureRecognizer) {
        onReorderGesture?(gesture)
    }

    @objc private func headerPlusTapped() {
        onNewTask?(plusButton)
    }
}

final class TaskCardView: UIView {
    static let contentInset: CGFloat = 18
    static let cornerRadius: CGFloat = 24

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tagsStack = UIStackView()
    private let flagView = UIImageView()
    private var titleToFlagConstraint: NSLayoutConstraint?
    private(set) var taskID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(task: BoardTask) {
        taskID = task.id
        titleLabel.text = task.title
        subtitleLabel.text = task.subtitle
        subtitleLabel.isHidden = task.subtitle.isEmpty
        tagsStack.arrangedSubviews.forEach { view in
            tagsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        task.tags.forEach { tag in
            tagsStack.addArrangedSubview(Self.makeTagView(tag))
        }
        tagsStack.isHidden = task.tags.isEmpty
        flagView.isHidden = !task.isFlagged
        titleToFlagConstraint?.isActive = task.isFlagged
    }

    private func configure() {
        // Обычная белая карточка со светло-серой обводкой
        backgroundColor = .white
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        tagsStack.axis = .horizontal
        tagsStack.spacing = 6
        tagsStack.alignment = .center
        tagsStack.distribution = .fill
        tagsStack.setContentCompressionResistancePriority(.required, for: .vertical)
        tagsStack.setContentHuggingPriority(.required, for: .vertical)

        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        flagView.image = UIImage(systemName: "flag.fill", withConfiguration: config)
        flagView.tintColor = .flag
        flagView.contentMode = .scaleAspectFit
        flagView.isHidden = true
        flagView.translatesAutoresizingMaskIntoConstraints = false
        flagView.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, tagsStack])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(flagView)

        let titleToFlag = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: flagView.leadingAnchor, constant: -8)
        titleToFlagConstraint = titleToFlag

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentInset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentInset),

            flagView.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentInset - 2),
            flagView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentInset),
            flagView.widthAnchor.constraint(equalToConstant: 16),
            flagView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private static func makeTagView(_ tag: TaskTag) -> UIView {
        let label = PaddingLabel()
        label.text = tag.title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = tag.color
        label.backgroundColor = tag.color.withAlphaComponent(0.14)
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        return label
    }
}

private final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets.zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }
}
