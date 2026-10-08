import UIKit

final class FiltersViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private enum Section: Int, CaseIterable {
        case content
        case status
        case people
        case interval
    }

    private let contentItems = ["С флажком", "Выполнено", "Не выполнено", "Просрочено"]
    private let contentSymbols = ["flag.fill", "checkmark.circle", "minus.circle", "alarm"]
    private let statusItems = ["Новые", "В работе", "Завершенные"]
    private let peopleItems = ["Ответственный", "Автор", "Теги"]

    private let titleLabel = UILabel()
    private let checkButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var contentSelected = Set<Int>()
    private var statusSelected = Set<Int>()
    private var intervalEnabled = false
    private var intervalStart = Date()
    private var intervalEnd = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.45)
        view.tintColor = .notesAccent
        preferredContentSize = CGSize(width: 360, height: 520)
        configureChrome()
        configureTable()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        relayoutPopover()
    }

    private func configureChrome() {
        titleLabel.text = "Фильтры"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        var config = UIButton.Configuration.prominentGlass()
        config.image = UIImage(systemName: "checkmark", withConfiguration: symbol)
        config.baseForegroundColor = .white
        config.background.backgroundColor = .notesAccent
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        checkButton.configuration = config
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        checkButton.accessibilityLabel = "Готово"
        checkButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(checkButton)

        NSLayoutConstraint.activate([
            checkButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            checkButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            checkButton.widthAnchor.constraint(equalToConstant: 32),
            checkButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: checkButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkButton.leadingAnchor, constant: -8)
        ])
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.sectionHeaderTopPadding = 0
        tableView.contentInset.top = -16
        tableView.rowHeight = 44
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "check")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "people")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "interval")
        tableView.register(IntervalDateCell.self, forCellReuseIdentifier: IntervalDateCell.reuseID)
        view.addSubview(tableView)
        view.bringSubviewToFront(titleLabel)
        view.bringSubviewToFront(checkButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: checkButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func relayoutPopover() {
        tableView.layoutIfNeeded()
        let height = 48 + tableView.contentSize.height
        let size = CGSize(width: 360, height: min(max(height, 420), 520))
        if preferredContentSize != size {
            preferredContentSize = size
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func intervalToggled(_ sender: UISwitch) {
        intervalEnabled = sender.isOn
        tableView.reloadRows(
            at: [
                IndexPath(row: 1, section: Section.interval.rawValue),
                IndexPath(row: 2, section: Section.interval.rawValue)
            ],
            with: .none
        )
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .content: return contentItems.count
        case .status: return statusItems.count
        case .people: return peopleItems.count
        case .interval: return 3
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .content: return "Содержание"
        case .status: return "Статус задачи"
        case .people, .interval, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .content:
            return checkCell(
                tableView.dequeueReusableCell(withIdentifier: "check", for: indexPath),
                title: contentItems[indexPath.row],
                symbol: contentSymbols[indexPath.row],
                selected: contentSelected.contains(indexPath.row)
            )
        case .status:
            return checkCell(
                tableView.dequeueReusableCell(withIdentifier: "check", for: indexPath),
                title: statusItems[indexPath.row],
                symbol: nil,
                selected: statusSelected.contains(indexPath.row)
            )
        case .people:
            let cell = tableView.dequeueReusableCell(withIdentifier: "people", for: indexPath)
            var content = UIListContentConfiguration.valueCell()
            content.text = peopleItems[indexPath.row]
            content.secondaryText = "Все"
            content.prefersSideBySideTextAndSecondaryText = true
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .none
            paintCellWhite(cell)
            return cell
        case .interval:
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "interval", for: indexPath)
                var content = UIListContentConfiguration.cell()
                content.text = "Интервал"
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                let toggle = UISwitch()
                toggle.isOn = intervalEnabled
                toggle.onTintColor = .notesAccent
                toggle.addTarget(self, action: #selector(intervalToggled(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                paintCellWhite(cell)
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: IntervalDateCell.reuseID, for: indexPath) as! IntervalDateCell
            let isStart = indexPath.row == 1
            cell.titleLabel.text = isStart ? "Начало" : "Конец"
            cell.datePicker.date = isStart ? intervalStart : intervalEnd
            cell.datePicker.removeTarget(nil, action: nil, for: .valueChanged)
            cell.datePicker.addTarget(
                self,
                action: isStart ? #selector(startChanged(_:)) : #selector(endChanged(_:)),
                for: .valueChanged
            )
            cell.setPickersEnabled(intervalEnabled)
            paintCellWhite(cell)
            return cell
        case .none:
            return UITableViewCell()
        }
    }

    private func checkCell(_ cell: UITableViewCell, title: String, symbol: String?, selected: Bool) -> UITableViewCell {
        var content = UIListContentConfiguration.cell()
        content.text = title
        if let symbol {
            content.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(weight: UIImage.appSymbolWeight)
            )
            content.imageProperties.tintColor = symbol == "flag.fill" ? .flag : .notesAccent
        }
        cell.contentConfiguration = content
        cell.selectionStyle = .default
        cell.accessoryType = selected ? .checkmark : .none
        cell.tintColor = .notesAccent
        paintCellWhite(cell)
        return cell
    }

    private func paintCellWhite(_ cell: UITableViewCell) {
        cell.backgroundColor = .systemBackground
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .systemBackground
        cell.backgroundConfiguration = background
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .content:
            if contentSelected.contains(indexPath.row) {
                contentSelected.remove(indexPath.row)
            } else {
                contentSelected.insert(indexPath.row)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
        case .status:
            if statusSelected.contains(indexPath.row) {
                statusSelected.remove(indexPath.row)
            } else {
                statusSelected.insert(indexPath.row)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
        case .people, .interval, .none:
            break
        }
    }

    @objc private func startChanged(_ sender: UIDatePicker) {
        intervalStart = sender.date
        if intervalEnd < intervalStart {
            intervalEnd = intervalStart
            reloadDateRow(2)
        }
    }

    @objc private func endChanged(_ sender: UIDatePicker) {
        intervalEnd = sender.date
        if intervalEnd < intervalStart {
            intervalStart = intervalEnd
            reloadDateRow(1)
        }
    }

    private func reloadDateRow(_ row: Int) {
        tableView.reloadRows(at: [IndexPath(row: row, section: Section.interval.rawValue)], with: .none)
    }
}

private final class IntervalDateCell: UITableViewCell {
    static let reuseID = "intervalDate"

    let titleLabel = UILabel()
    let datePicker = UIDatePicker()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.locale = Locale(identifier: "ru_RU")
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(datePicker)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            datePicker.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            datePicker.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: datePicker.leadingAnchor, constant: -8),
            contentView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    func setPickersEnabled(_ enabled: Bool) {
        datePicker.isEnabled = true
        datePicker.isUserInteractionEnabled = enabled
        datePicker.alpha = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
