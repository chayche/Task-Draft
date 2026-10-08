import UIKit

final class NewBoardViewController: UIViewController, UITextFieldDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onCreate: ((Board) -> Void)?
    /// Доска для редактирования. Если задана — экран работает в режиме «Изменить доску».
    var editingBoard: Board?
    private var isEditingBoard: Bool { editingBoard != nil }

    private let closeButton = UIButton(type: .system)
    private let checkButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let segment = UISegmentedControl(items: ["Новая доска", "Шаблоны"])
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let templatesPlaceholder = UIView()

    private let identityCard = UIView()
    private let avatarGlow = UIView()
    private let avatarCircle = UIView()
    private let avatarIcon = UIImageView()
    private let avatarEmoji = UILabel()
    private let nameField = UITextField()

    private let colorCard = UIView()
    private let iconCard = UIView()
    private var iconCollection: UICollectionView!
    private var iconCollectionHeight: NSLayoutConstraint?

    private let emojiField = UITextField()

    private let palette: [UIColor] = [
        UIColor(red: 255 / 255, green: 59 / 255, blue: 48 / 255, alpha: 1),
        UIColor(red: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1),
        UIColor(red: 255 / 255, green: 204 / 255, blue: 0 / 255, alpha: 1),
        UIColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1),
        .notesAccent,
        UIColor(red: 90 / 255, green: 200 / 255, blue: 250 / 255, alpha: 1),
        UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1),
        UIColor(red: 88 / 255, green: 86 / 255, blue: 214 / 255, alpha: 1),
        UIColor(red: 255 / 255, green: 45 / 255, blue: 85 / 255, alpha: 1),
        UIColor(red: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1),
        UIColor(red: 162 / 255, green: 132 / 255, blue: 94 / 255, alpha: 1),
        UIColor(red: 99 / 255, green: 99 / 255, blue: 102 / 255, alpha: 1),
        UIColor(red: 199 / 255, green: 160 / 255, blue: 138 / 255, alpha: 1)
    ]

    private static let iconSymbols = [
        "columns-3",
        "bookmark.fill",
        "key.fill",
        "gift.fill",
        "birthday.cake.fill",
        "graduationcap.fill",
        "list.clipboard.fill",
        "pencil.circle.fill",
        "doc.fill",
        "book.fill",
        "backpack.fill",
        "creditcard.fill",
        "banknote.fill",
        "dumbbell.fill",
        "figure.run.circle.fill",
        "fork.knife",
        "wineglass.fill",
        "pills.fill",
        "cross.case.fill",
        "chair.fill",
        "house.fill",
        "building.2.fill",
        "building.columns.fill",
        "tent.fill",
        "tv.fill",
        "music.note.house.fill",
        "keyboard.fill",
        "gamecontroller.fill",
        "headphones.circle.fill",
        "leaf.fill",
        "carrot.fill",
        "person.fill",
        "person.2.fill",
        "person.3.fill",
        "pawprint.fill",
        "teddybear.fill",
        "fish.fill",
        "basket.fill",
        "cart.fill",
        "bag.fill",
        "shippingbox.fill",
        "soccerball.inverse",
        "baseball.fill",
        "basketball.fill",
        "football.fill",
        "trophy.fill",
        "tram.fill",
        "airplane.circle.fill",
        "sailboat.fill",
        "car.fill",
        "beach.umbrella.fill",
        "sun.max.fill",
        "moon.fill",
        "drop.fill",
        "snowflake.circle.fill",
        "flame.fill",
        "briefcase.fill",
        "wrench.and.screwdriver.fill",
        "scissors.circle.fill"
    ]

    /// Новая доска получает случайный цвет из палитры
    private lazy var selectedColorIndex = Int.random(in: 0..<palette.count)
    private var selectedSymbol = "columns-3"
    private var selectedEmoji: String?
    private var colorButtons: [UIButton] = []
    private var checkShowsGlass = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = .notesAccent
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: 540, height: 760)
        prefillFromEditingBoard()
        configureChrome()
        configureSegment()
        configureScroll()
        configureIdentityCard()
        configureColorCard()
        configureIconCard()
        configureEmojiField()
        configureTemplatesPlaceholder()
        if let board = editingBoard {
            nameField.text = board.title
        }
        updateAvatar()
        updateCheckEnabled()
    }

    private func prefillFromEditingBoard() {
        guard let board = editingBoard else { return }
        selectedEmoji = (board.emoji?.isEmpty == false) ? board.emoji : nil
        if selectedEmoji == nil {
            selectedSymbol = board.symbolName
        }
        if let index = palette.firstIndex(where: { Self.colorsMatch($0, board.iconBottom) }) {
            selectedColorIndex = index
        }
    }

    private static func colorsMatch(_ a: UIColor, _ b: UIColor) -> Bool {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return false }
        let eps: CGFloat = 0.01
        return abs(r1 - r2) < eps && abs(g1 - g2) < eps && abs(b1 - b2) < eps
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Клавиатуру сразу не поднимаем: на iPad она выталкивает окно вверх и сжимает его.
        // Показываем, что список иконок прокручивается
        scrollView.flashScrollIndicators()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateIconCollectionHeight()
        // Квадратная иконка с тем же скруглением, что у досок в сайдбаре
        let avatarRadius = avatarCircle.bounds.width * GradientIconPlate.cornerRatio
        avatarCircle.layer.cornerRadius = avatarRadius
        avatarCircle.layer.cornerCurve = .continuous
        let glowInset = max((avatarGlow.bounds.width - avatarCircle.bounds.width) / 2, 0)
        avatarGlow.layer.shadowPath = UIBezierPath(
            roundedRect: avatarGlow.bounds.insetBy(dx: glowInset, dy: glowInset),
            cornerRadius: avatarRadius
        ).cgPath
    }

    private func configureChrome() {
        titleLabel.text = isEditingBoard ? "Изменить доску" : "Новая доска"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        styleCircleButton(closeButton, symbol: "xmark", enabled: true)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.accessibilityLabel = "Закрыть"

        styleCircleButton(checkButton, symbol: "checkmark", enabled: false)
        checkButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        checkButton.accessibilityLabel = "Сохранить"
        checkButton.setContentHuggingPriority(.required, for: .horizontal)
        checkButton.setContentHuggingPriority(.required, for: .vertical)
        checkButton.setContentCompressionResistancePriority(.required, for: .vertical)

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(checkButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            checkButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            checkButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            checkButton.widthAnchor.constraint(equalToConstant: 32),
            checkButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkButton.leadingAnchor, constant: -8)
        ])
    }

    private func styleCircleButton(_ button: UIButton, symbol: String, enabled: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 16
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = enabled ? .label : .tertiaryLabel
        button.isEnabled = enabled || button === closeButton
    }

    private func configureSegment() {
        segment.selectedSegmentIndex = 0
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.isHidden = isEditingBoard
        segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        view.addSubview(segment)
        NSLayoutConstraint.activate([
            segment.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 14),
            segment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            segment.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func configureScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            isEditingBoard
                ? scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 14)
                : scrollView.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func configureIdentityCard() {
        styleCard(identityCard)
        identityCard.clipsToBounds = false

        avatarGlow.translatesAutoresizingMaskIntoConstraints = false
        avatarGlow.backgroundColor = .clear
        avatarGlow.isUserInteractionEnabled = false

        avatarCircle.translatesAutoresizingMaskIntoConstraints = false
        avatarCircle.clipsToBounds = true

        avatarIcon.translatesAutoresizingMaskIntoConstraints = false
        avatarIcon.contentMode = .scaleAspectFit
        avatarIcon.tintColor = .white

        avatarEmoji.translatesAutoresizingMaskIntoConstraints = false
        avatarEmoji.font = .systemFont(ofSize: 42)
        avatarEmoji.textAlignment = .center
        avatarEmoji.isHidden = true

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholder = "Название"
        nameField.textAlignment = .center
        nameField.font = .systemFont(ofSize: 17)
        nameField.backgroundColor = .tertiarySystemFill
        nameField.layer.cornerRadius = 12
        nameField.layer.cornerCurve = .continuous
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.returnKeyType = .done

        identityCard.addSubview(avatarGlow)
        identityCard.addSubview(avatarCircle)
        avatarCircle.addSubview(avatarIcon)
        avatarCircle.addSubview(avatarEmoji)
        identityCard.addSubview(nameField)
        contentStack.addArrangedSubview(identityCard)

        NSLayoutConstraint.activate([
            avatarCircle.topAnchor.constraint(equalTo: identityCard.topAnchor, constant: 28),
            avatarCircle.centerXAnchor.constraint(equalTo: identityCard.centerXAnchor),
            avatarCircle.widthAnchor.constraint(equalToConstant: 88),
            avatarCircle.heightAnchor.constraint(equalToConstant: 88),

            avatarGlow.centerXAnchor.constraint(equalTo: avatarCircle.centerXAnchor),
            avatarGlow.centerYAnchor.constraint(equalTo: avatarCircle.centerYAnchor),
            avatarGlow.widthAnchor.constraint(equalToConstant: 120),
            avatarGlow.heightAnchor.constraint(equalToConstant: 120),

            avatarIcon.centerXAnchor.constraint(equalTo: avatarCircle.centerXAnchor),
            avatarIcon.centerYAnchor.constraint(equalTo: avatarCircle.centerYAnchor),
            avatarIcon.widthAnchor.constraint(equalToConstant: 40),
            avatarIcon.heightAnchor.constraint(equalToConstant: 40),

            avatarEmoji.centerXAnchor.constraint(equalTo: avatarCircle.centerXAnchor),
            avatarEmoji.centerYAnchor.constraint(equalTo: avatarCircle.centerYAnchor),

            nameField.topAnchor.constraint(equalTo: avatarCircle.bottomAnchor, constant: 22),
            nameField.leadingAnchor.constraint(equalTo: identityCard.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: identityCard.trailingAnchor, constant: -16),
            nameField.heightAnchor.constraint(equalToConstant: 50),
            nameField.bottomAnchor.constraint(equalTo: identityCard.bottomAnchor, constant: -16)
        ])
    }

    private func configureColorCard() {
        styleCard(colorCard)
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false
        colorCard.addSubview(grid)

        let first = UIStackView()
        first.axis = .horizontal
        first.spacing = 0
        first.distribution = .fillEqually
        first.alignment = .center

        let second = UIStackView()
        second.axis = .horizontal
        second.spacing = 0
        second.distribution = .fillEqually
        second.alignment = .center

        for (index, color) in palette.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = color
            button.layer.cornerRadius = 16
            button.clipsToBounds = true
            button.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32),
                button.heightAnchor.constraint(equalToConstant: 32)
            ])
            colorButtons.append(button)
            let slot = UIView()
            slot.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                slot.heightAnchor.constraint(equalToConstant: 32)
            ])
            if index < 10 {
                first.addArrangedSubview(slot)
            } else {
                second.addArrangedSubview(slot)
            }
        }
        while second.arrangedSubviews.count < 10 {
            let empty = UIView()
            empty.heightAnchor.constraint(equalToConstant: 32).isActive = true
            second.addArrangedSubview(empty)
        }

        grid.addArrangedSubview(first)
        grid.addArrangedSubview(second)
        contentStack.addArrangedSubview(colorCard)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: colorCard.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: colorCard.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: colorCard.trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: colorCard.bottomAnchor, constant: -16)
        ])
        refreshColorSelection()
    }

    private func configureIconCard() {
        styleCard(iconCard)
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        iconCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        iconCollection.translatesAutoresizingMaskIntoConstraints = false
        iconCollection.backgroundColor = .clear
        iconCollection.isScrollEnabled = false
        iconCollection.dataSource = self
        iconCollection.delegate = self
        iconCollection.register(BoardIconCell.self, forCellWithReuseIdentifier: BoardIconCell.reuseID)
        iconCard.addSubview(iconCollection)
        contentStack.addArrangedSubview(iconCard)

        let height = iconCollection.heightAnchor.constraint(equalToConstant: 240)
        iconCollectionHeight = height
        NSLayoutConstraint.activate([
            iconCollection.topAnchor.constraint(equalTo: iconCard.topAnchor, constant: 14),
            iconCollection.leadingAnchor.constraint(equalTo: iconCard.leadingAnchor, constant: 12),
            iconCollection.trailingAnchor.constraint(equalTo: iconCard.trailingAnchor, constant: -12),
            iconCollection.bottomAnchor.constraint(equalTo: iconCard.bottomAnchor, constant: -14),
            height
        ])
    }

    private func configureEmojiField() {
        emojiField.delegate = self
        emojiField.autocorrectionType = .no
        emojiField.spellCheckingType = .no
        emojiField.alpha = 0.02
        emojiField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emojiField)
        NSLayoutConstraint.activate([
            emojiField.widthAnchor.constraint(equalToConstant: 1),
            emojiField.heightAnchor.constraint(equalToConstant: 1),
            emojiField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiField.topAnchor.constraint(equalTo: view.topAnchor)
        ])
    }

    private func configureTemplatesPlaceholder() {
        templatesPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        templatesPlaceholder.isHidden = true
        view.addSubview(templatesPlaceholder)
        NSLayoutConstraint.activate([
            templatesPlaceholder.topAnchor.constraint(equalTo: scrollView.topAnchor),
            templatesPlaceholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            templatesPlaceholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            templatesPlaceholder.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func styleCard(_ card: UIView) {
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateIconCollectionHeight() {
        iconCollection.layoutIfNeeded()
        let width = iconCollection.bounds.width
        guard width > 0 else { return }
        let item = iconItemSize(for: width)
        let rows = ceil(CGFloat(collectionView(iconCollection, numberOfItemsInSection: 0)) / 10)
        let height = rows * item.height + max(rows - 1, 0) * 10
        if iconCollectionHeight?.constant != height {
            iconCollectionHeight?.constant = height
        }
    }

    private func iconItemSize(for width: CGFloat) -> CGSize {
        let spacing: CGFloat = 8
        let side = max(floor((width - spacing * 9) / 10), 24)
        return CGSize(width: side, height: side)
    }

    private func updateAvatar() {
        let color = palette[selectedColorIndex]
        avatarCircle.backgroundColor = color
        avatarGlow.layer.shadowColor = color.cgColor
        avatarGlow.layer.shadowRadius = 24
        avatarGlow.layer.shadowOpacity = 0.7
        avatarGlow.layer.shadowOffset = .zero
        avatarGlow.backgroundColor = .clear

        if let emoji = selectedEmoji {
            avatarEmoji.isHidden = false
            avatarIcon.isHidden = true
            avatarEmoji.text = emoji
        } else {
            avatarEmoji.isHidden = true
            avatarIcon.isHidden = false
            avatarIcon.image = Self.image(for: selectedSymbol, pointSize: 28)
        }
        refreshColorSelection()
        iconCollection?.reloadData()
    }

    private func refreshColorSelection() {
        for (index, button) in colorButtons.enumerated() {
            let selected = index == selectedColorIndex
            button.layer.borderWidth = selected ? 3 : 0
            button.layer.borderColor = UIColor.white.cgColor
            button.layer.shadowOpacity = selected ? 0.25 : 0
            button.layer.shadowRadius = 3
            button.layer.shadowOffset = .zero
            button.layer.shadowColor = UIColor.black.cgColor
            button.transform = selected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }

    private func updateCheckEnabled() {
        let hasName = !(nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        checkButton.isEnabled = hasName
        guard checkShowsGlass != hasName else { return }
        checkShowsGlass = hasName
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        let check = UIImage(systemName: "checkmark", withConfiguration: symbol)
        if hasName {
            var config = UIButton.Configuration.prominentGlass()
            config.image = check
            config.baseForegroundColor = .white
            config.background.backgroundColor = .notesAccent
            config.cornerStyle = .capsule
            config.buttonSize = .small
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            checkButton.configuration = config
            checkButton.backgroundColor = .clear
            checkButton.tintColor = .white
        } else {
            checkButton.configuration = nil
            checkButton.backgroundColor = .tertiarySystemFill
            checkButton.layer.cornerRadius = 16
            checkButton.setImage(check, for: .normal)
            checkButton.tintColor = .tertiaryLabel
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let title = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let color = palette[selectedColorIndex]
        let board = Board(
            id: editingBoard?.id ?? UUID().uuidString,
            title: title,
            symbolName: selectedEmoji == nil ? selectedSymbol : "person.fill",
            iconTop: color.lighter(by: 0.12),
            iconBottom: color,
            columns: editingBoard?.columns ?? [
                BoardColumn(title: "Новые", tasks: []),
                BoardColumn(title: "В работе", tasks: []),
                BoardColumn(title: "На проверке", tasks: []),
                BoardColumn(title: "Завершено", tasks: [])
            ],
            emoji: selectedEmoji
        )
        onCreate?(board)
        dismiss(animated: true)
    }

    @objc private func segmentChanged() {
        let templates = segment.selectedSegmentIndex == 1
        scrollView.isHidden = templates
        templatesPlaceholder.isHidden = !templates
        if templates {
            view.endEditing(true)
        }
    }

    @objc private func nameChanged() {
        updateCheckEnabled()
    }

    @objc private func colorTapped(_ sender: UIButton) {
        selectedColorIndex = sender.tag
        updateAvatar()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === emojiField else { return true }
        if !string.isEmpty {
            selectedEmoji = string
            view.endEditing(true)
            updateAvatar()
        }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        1 + Self.iconSymbols.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BoardIconCell.reuseID, for: indexPath) as! BoardIconCell
        if indexPath.item == 0 {
            cell.applySmile(selected: selectedEmoji != nil)
        } else {
            let symbol = Self.iconSymbols[indexPath.item - 1]
            let selected = selectedEmoji == nil && symbol == selectedSymbol
            cell.apply(symbol: symbol, selected: selected)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == 0 {
            nameField.resignFirstResponder()
            emojiField.becomeFirstResponder()
            return
        }
        selectedEmoji = nil
        selectedSymbol = Self.iconSymbols[indexPath.item - 1]
        emojiField.resignFirstResponder()
        updateAvatar()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        iconItemSize(for: collectionView.bounds.width)
    }

    static func image(for symbol: String, pointSize: CGFloat) -> UIImage? {
        if symbol == "columns-3" {
            return UIImage(named: "columns-3")?.withRenderingMode(.alwaysTemplate)
        }
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: UIImage.appSymbolWeight)
        return UIImage(systemName: symbol, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
    }
}

private final class BoardIconCell: UICollectionViewCell {
    static let reuseID = "BoardIcon"
    private let ring = UIView()
    private let body = UIView()
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.backgroundColor = .clear
        contentView.addSubview(ring)

        body.backgroundColor = .tertiarySystemFill
        body.clipsToBounds = true
        contentView.addSubview(body)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        body.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: body.centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.52),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(contentView.bounds.width, contentView.bounds.height)
        let origin = CGPoint(
            x: contentView.bounds.midX - side / 2,
            y: contentView.bounds.midY - side / 2
        )
        ring.frame = CGRect(origin: origin, size: CGSize(width: side, height: side))
        ring.layer.cornerRadius = side / 2
        let inset: CGFloat = 4
        let bodySide = max(side - inset * 2, 0)
        body.frame = CGRect(
            x: ring.frame.midX - bodySide / 2,
            y: ring.frame.midY - bodySide / 2,
            width: bodySide,
            height: bodySide
        )
        body.layer.cornerRadius = bodySide / 2
    }

    func apply(symbol: String, selected: Bool) {
        iconView.tintColor = .label
        iconView.image = NewBoardViewController.image(for: symbol, pointSize: 15)
        body.backgroundColor = .tertiarySystemFill
        applySelection(selected)
    }

    func applySmile(selected: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: UIImage.appSymbolWeight)
        iconView.image = UIImage(systemName: "face.smiling", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .white
        body.backgroundColor = .systemBlue
        applySelection(selected)
    }

    private func applySelection(_ selected: Bool) {
        ring.backgroundColor = selected ? .white : .clear
        ring.layer.borderWidth = selected ? 2 : 0
        ring.layer.borderColor = UIColor.systemGray2.cgColor
        ring.clipsToBounds = true
    }
}

extension UIColor {
    func lighter(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: min(r + amount, 1), green: min(g + amount, 1), blue: min(b + amount, 1), alpha: a)
    }
}
