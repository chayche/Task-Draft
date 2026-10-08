import UIKit

/// Выбор тегов задачи: список с отметками и строка «Новый тег»
final class TaskTagsViewController: UITableViewController {
    var onChange: (([TaskTag]) -> Void)?
    private var selected: [TaskTag]

    init(selected: [TaskTag]) {
        self.selected = selected
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Теги"
        view.tintColor = DetailTheme.accent
        tableView.backgroundColor = .detailBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Tag")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? TagLibrary.all.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Tag", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let tag = TagLibrary.all[indexPath.row]
            content.text = tag.title
            content.image = UIImage(systemName: "circle.fill")
            content.imageProperties.tintColor = tag.color
            content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14)
            cell.accessoryType = isSelected(tag) ? .checkmark : .none
        } else {
            content.text = "Новый тег"
            content.textProperties.color = DetailTheme.accent
            content.image = UIImage(systemName: "plus.circle.fill")
            content.imageProperties.tintColor = DetailTheme.accent
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
        cell.backgroundColor = .detailGroup
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else {
            openNewTag()
            return
        }
        let tag = TagLibrary.all[indexPath.row]
        if isSelected(tag) {
            selected.removeAll { $0.title == tag.title }
        } else {
            selected.append(tag)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        onChange?(selected)
    }

    private func isSelected(_ tag: TaskTag) -> Bool {
        selected.contains { $0.title == tag.title }
    }

    private func openNewTag() {
        let editor = NewTagViewController()
        editor.onCreate = { [weak self] tag in
            guard let self else { return }
            TagLibrary.custom.append(tag)
            self.selected.append(tag)
            self.tableView.reloadData()
            self.onChange?(self.selected)
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(width: 420, height: 380)
        present(nav, animated: true)
    }
}

/// Создание тега: название, цвет и живое превью капсулы
final class NewTagViewController: UIViewController, UITextFieldDelegate {
    var onCreate: ((TaskTag) -> Void)?

    private let nameField = UITextField()
    private let preview = UILabel()
    private var colorButtons: [UIButton] = []
    private var selectedColor = TagLibrary.colors[6]
    private var doneItem: UIBarButtonItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Новый тег"
        view.backgroundColor = .detailBackground
        view.tintColor = DetailTheme.accent
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        let done = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.create() }
        )
        done.isEnabled = false
        doneItem = done
        navigationItem.rightBarButtonItem = done

        preview.font = .systemFont(ofSize: 17, weight: .semibold)
        preview.textAlignment = .center
        preview.layer.cornerRadius = 12
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true

        nameField.placeholder = "Название тега"
        nameField.font = .preferredFont(forTextStyle: .body)
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.addAction(UIAction { [weak self] _ in self?.updatePreview() }, for: .editingChanged)
        let nameGroup = GroupView(rows: [TaskDetailViewController.paddedRow(nameField, minHeight: 52)])

        let colorsGrid = UIStackView()
        colorsGrid.axis = .vertical
        colorsGrid.spacing = 14
        for rowColors in stride(from: 0, to: TagLibrary.colors.count, by: 6).map({
            Array(TagLibrary.colors[$0..<min($0 + 6, TagLibrary.colors.count)])
        }) {
            let row = UIStackView()
            row.distribution = .equalSpacing
            for color in rowColors {
                let button = UIButton(type: .custom)
                button.backgroundColor = color
                button.layer.cornerRadius = 18
                button.translatesAutoresizingMaskIntoConstraints = false
                button.widthAnchor.constraint(equalToConstant: 36).isActive = true
                button.heightAnchor.constraint(equalToConstant: 36).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    self?.selectedColor = color
                    self?.updatePreview()
                }, for: .touchUpInside)
                colorButtons.append(button)
                row.addArrangedSubview(button)
            }
            colorsGrid.addArrangedSubview(row)
        }
        let colorsGroup = GroupView(rows: [TaskDetailViewController.inset(colorsGrid, leading: 20, trailing: 20)])
        colorsGrid.superview?.layoutMargins = .zero
        colorsGrid.isLayoutMarginsRelativeArrangement = true
        colorsGrid.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 0, bottom: 18, trailing: 0)

        let stack = UIStackView(arrangedSubviews: [TaskDetailViewController.inset(preview), nameGroup, colorsGroup])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            preview.heightAnchor.constraint(equalToConstant: 44)
        ])
        updatePreview()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameField.becomeFirstResponder()
    }

    private func updatePreview() {
        let name = nameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        preview.text = name.isEmpty ? "Тег" : name
        preview.textColor = selectedColor
        preview.backgroundColor = selectedColor.withAlphaComponent(0.14)
        doneItem?.isEnabled = !name.isEmpty
        for button in colorButtons {
            let selected = button.backgroundColor == selectedColor
            button.layer.borderWidth = selected ? 3 : 0
            button.layer.borderColor = UIColor.systemBackground.cgColor
            button.layer.shadowColor = button.backgroundColor?.cgColor
            button.layer.shadowOpacity = selected ? 1 : 0
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = .zero
            // Кольцо выбранного цвета: белая обводка внутри и цветная тень снаружи
            button.layer.shadowPath = selected
                ? UIBezierPath(ovalIn: CGRect(x: -3, y: -3, width: 42, height: 42)).cgPath
                : nil
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        create()
        return false
    }

    private func create() {
        let name = nameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return }
        onCreate?(TaskTag(title: name, color: selectedColor))
        dismiss(animated: true)
    }
}
