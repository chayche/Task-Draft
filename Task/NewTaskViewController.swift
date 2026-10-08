import UIKit

final class NewTaskViewController: UIViewController, UITextViewDelegate {
    var onCreate: ((String, Bool) -> Void)?

    private let closeButton = UIButton(type: .system)
    private let checkButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let fieldCard = UIView()
    private let titleView = UITextView()
    private let placeholderLabel = UILabel()
    private let flagCard = UIView()
    private let flagLabel = UILabel()
    private let flagSwitch = UISwitch()
    private var checkShowsGlass = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = .notesAccent
        view.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.45)
        preferredContentSize = CGSize(width: 380, height: 290)
        configureChrome()
        configureField()
        configureFlagRow()
        updateCheckEnabled()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if titleView.window != nil, !titleView.isFirstResponder {
            titleView.becomeFirstResponder()
        }
    }

    private func configureChrome() {
        titleLabel.text = "Задача"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        styleCloseButton()
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.accessibilityLabel = "Закрыть"

        styleIdleCheckButton()
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
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
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

    private func symbolImage(_ name: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        return UIImage(systemName: name, withConfiguration: config)
    }

    private func styleCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = .systemBackground
        closeButton.layer.cornerRadius = 16
        closeButton.clipsToBounds = false
        closeButton.layer.masksToBounds = false
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOpacity = 0.12
        closeButton.layer.shadowRadius = 6
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        closeButton.setImage(symbolImage("xmark"), for: .normal)
        closeButton.tintColor = .label
    }

    private func styleIdleCheckButton() {
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        checkButton.configuration = nil
        checkButton.backgroundColor = .systemGray3
        checkButton.layer.cornerRadius = 16
        checkButton.adjustsImageWhenDisabled = false
        checkButton.setImage(symbolImage("checkmark"), for: .normal)
        checkButton.tintColor = .white
    }

    private func configureField() {
        fieldCard.translatesAutoresizingMaskIntoConstraints = false
        fieldCard.backgroundColor = .systemBackground
        fieldCard.layer.cornerRadius = 16
        fieldCard.layer.cornerCurve = .continuous
        view.addSubview(fieldCard)

        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.font = .systemFont(ofSize: 17)
        titleView.backgroundColor = .clear
        titleView.textContainerInset = .zero
        titleView.textContainer.lineFragmentPadding = 0
        titleView.delegate = self
        titleView.returnKeyType = .default
        fieldCard.addSubview(titleView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Напишите, что нужно сделать"
        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        fieldCard.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            fieldCard.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            fieldCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fieldCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            titleView.topAnchor.constraint(equalTo: fieldCard.topAnchor, constant: 14),
            titleView.leadingAnchor.constraint(equalTo: fieldCard.leadingAnchor, constant: 14),
            titleView.trailingAnchor.constraint(equalTo: fieldCard.trailingAnchor, constant: -14),
            titleView.bottomAnchor.constraint(equalTo: fieldCard.bottomAnchor, constant: -14),
            titleView.heightAnchor.constraint(equalToConstant: 96),

            placeholderLabel.topAnchor.constraint(equalTo: titleView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: titleView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: titleView.trailingAnchor)
        ])
    }

    private func configureFlagRow() {
        flagCard.translatesAutoresizingMaskIntoConstraints = false
        flagCard.backgroundColor = .systemBackground
        flagCard.layer.cornerRadius = 16
        flagCard.layer.cornerCurve = .continuous
        view.addSubview(flagCard)

        flagLabel.translatesAutoresizingMaskIntoConstraints = false
        flagLabel.text = "Пометить флажком"
        flagLabel.font = .systemFont(ofSize: 17)
        flagCard.addSubview(flagLabel)

        flagSwitch.translatesAutoresizingMaskIntoConstraints = false
        flagSwitch.onTintColor = .notesAccent
        flagCard.addSubview(flagSwitch)

        NSLayoutConstraint.activate([
            flagCard.topAnchor.constraint(equalTo: fieldCard.bottomAnchor, constant: 12),
            flagCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            flagCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flagCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            flagLabel.leadingAnchor.constraint(equalTo: flagCard.leadingAnchor, constant: 14),
            flagLabel.centerYAnchor.constraint(equalTo: flagCard.centerYAnchor),
            flagSwitch.trailingAnchor.constraint(equalTo: flagCard.trailingAnchor, constant: -14),
            flagSwitch.centerYAnchor.constraint(equalTo: flagCard.centerYAnchor),
            flagLabel.trailingAnchor.constraint(lessThanOrEqualTo: flagSwitch.leadingAnchor, constant: -8),
            flagCard.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func updateCheckEnabled() {
        let hasText = !titleView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        placeholderLabel.isHidden = !titleView.text.isEmpty
        checkButton.isEnabled = hasText
        guard checkShowsGlass != hasText else { return }
        checkShowsGlass = hasText
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: UIImage.appSymbolWeight)
        let check = UIImage(systemName: "checkmark", withConfiguration: symbol)
        if hasText {
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
            styleIdleCheckButton()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        updateCheckEnabled()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let title = titleView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onCreate?(title, flagSwitch.isOn)
        dismiss(animated: true)
    }
}
