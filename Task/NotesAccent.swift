import UIKit

extension UIColor {
    static let notesAccent = UIColor(red: 11 / 255, green: 166 / 255, blue: 134 / 255, alpha: 1)
    /// Цвет флажка во всём приложении — системный оранжевый, как в «Почте»
    static let flag = UIColor.systemOrange
    static let notesAccentDark = UIColor(red: 6 / 255, green: 112 / 255, blue: 90 / 255, alpha: 1)
}

/// Иконки в строках списков — общие для сайдбара и карточки задачи
enum ListIconStyle {
    /// Размер цветной плашки доски и аватара
    static let plateSize: CGFloat = 28
    /// Доля плашки, которую занимает белый символ внутри
    static let glyphRatio: CGFloat = 0.75
    /// Кегль линейных иконок слева от строк
    static let lineSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: UIImage.appSymbolWeight)
}

extension UIImage {
    /// «Добавить колонку»: колонка-скобка и круглый «+», наложенный на её правый край
    static func addColumnGlyph(size: CGFloat = 22) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            let unit = size / 24
            let line = 1.7 * unit
            UIColor.black.setStroke()
            UIColor.black.setFill()
            // Колонка
            let column = UIBezierPath(
                roundedRect: CGRect(x: 3 * unit, y: 2.5 * unit, width: 11 * unit, height: 19 * unit),
                cornerRadius: 2.2 * unit
            )
            column.lineWidth = line
            column.stroke()
            // Просвет вокруг кружка, затем сам кружок с вырезанным «+»
            let center = CGPoint(x: 15.5 * unit, y: 12 * unit)
            cg.setBlendMode(.clear)
            UIBezierPath(arcCenter: center, radius: 7.6 * unit, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            cg.setBlendMode(.normal)
            UIBezierPath(arcCenter: center, radius: 6 * unit, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            cg.setBlendMode(.clear)
            let arm = 3.3 * unit, thick = 1.6 * unit
            UIBezierPath(rect: CGRect(x: center.x - arm, y: center.y - thick / 2, width: arm * 2, height: thick)).fill()
            UIBezierPath(rect: CGRect(x: center.x - thick / 2, y: center.y - arm, width: thick, height: arm * 2)).fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

extension UIFont {
    /// Заголовок секции, как в сайдбарах и списках iPadOS: «Доски», «Детали задачи», «Люди», «Чек-лист»
    static var sectionHeader: UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        return UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
    }
}

extension UIImage {
    /// Единая толщина всех иконок в приложении
    static let appSymbolWeight: UIImage.SymbolWeight = .regular
    /// Кегль, в котором навбар рисует свои иконки (замер: «✕» в навбаре — 17 pt).
    /// Иконки в своих кнопках навбара рисуем так же — тогда размер и толщина совпадают
    static let barSymbolPointSize: CGFloat = 21.5

    /// Толщина, с которой навбар рисует системные иконки (сайдбар, лупа, капсула в центре)
    static let barSymbolWeight: UIImage.SymbolWeight = .regular

    static func notesBarGlyph(_ name: String) -> UIImage? {
        notesBarSymbol(name)?.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: barSymbolPointSize, weight: barSymbolWeight)
        )
    }

    static func notesBarSymbol(_ name: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(paletteColors: [.notesAccent, .notesAccent])
            .applying(UIImage.SymbolConfiguration(weight: appSymbolWeight))
        return UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(.notesAccent, renderingMode: .alwaysOriginal)
    }
}

extension UIBarButtonItem {
    func applyNotesAccent() {
        tintColor = .notesAccent
        if let image, image.renderingMode != .alwaysOriginal {
            self.image = image.withTintColor(.notesAccent, renderingMode: .alwaysOriginal)
        }
    }

    static func notesRoundBarButton(
        symbol: String,
        target: Any?,
        action: Selector?,
        accessibilityLabel: String
    ) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.glass()
        config.image = .notesBarSymbol(symbol)
        config.cornerStyle = .capsule
        config.buttonSize = .medium
        config.baseForegroundColor = .notesAccent
        button.configuration = config
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        if let target, let action {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        button.accessibilityLabel = accessibilityLabel
        let item = UIBarButtonItem(customView: button)
        item.hidesSharedBackground = true
        return item
    }

    /// Круглая стеклянная «+», по нажатию открывает меню создания
    static func notesAddMenuButton(menu: UIMenu) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: .notesBarGlyph("plus"), menu: menu)
        item.accessibilityLabel = "Добавить"
        return item
    }

    static func notesPlainIconButton(
        symbol: String,
        target: Any?,
        action: Selector?,
        accessibilityLabel: String
    ) -> UIBarButtonItem {
        let button = UIButton(type: .system)
        button.setImage(.notesBarSymbol(symbol), for: .normal)
        button.tintColor = .notesAccent
        button.frame = CGRect(x: 0, y: 0, width: 36, height: 44)
        if let target, let action {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        button.accessibilityLabel = accessibilityLabel
        let item = UIBarButtonItem(customView: button)
        item.hidesSharedBackground = true
        item.applyNotesAccent()
        return item
    }
}

extension UIView {
    func applyNotesAccentToBarSymbols() {
        tintColor = .notesAccent
        if let imageView = self as? UIImageView {
            if imageView.image?.renderingMode == .alwaysOriginal {
                return
            }
            imageView.tintColor = .notesAccent
            imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
        }
        if let button = self as? UIButton {
            if button.image(for: .normal)?.renderingMode == .alwaysOriginal {
                return
            }
            button.tintColor = .notesAccent
            if var configuration = button.configuration {
                configuration.baseForegroundColor = .notesAccent
                button.configuration = configuration
            }
        }
        subviews.forEach { $0.applyNotesAccentToBarSymbols() }
    }
}

extension UINavigationBar {
    func applyNotesAccentAppearance(showsInlineTitle: Bool = false) {
        tintColor = .notesAccent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        let headline = UIFont.preferredFont(forTextStyle: .headline)
        let subheadline = UIFont.preferredFont(forTextStyle: .subheadline)
        appearance.titleTextAttributes = [
            .foregroundColor: showsInlineTitle ? UIColor.label : UIColor.clear,
            .font: headline
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: headline
        ]
        appearance.subtitleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: subheadline
        ]
        appearance.largeSubtitleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: subheadline
        ]
        appearance.backButtonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.notesAccent
        ]
        // Стрелка «Назад» — фирменный зелёный
        if let chevron = UIImage(systemName: "chevron.backward",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: UIImage.barSymbolPointSize, weight: UIImage.barSymbolWeight))?
            .withTintColor(.notesAccent, renderingMode: .alwaysOriginal) {
            appearance.setBackIndicatorImage(chevron, transitionMaskImage: chevron)
        }
        let barButton = UIBarButtonItemAppearance()
        barButton.normal.titleTextAttributes = [
            .foregroundColor: UIColor.notesAccent
        ]
        appearance.buttonAppearance = barButton
        appearance.doneButtonAppearance = barButton
        standardAppearance = appearance
        scrollEdgeAppearance = appearance
        compactAppearance = appearance
        compactScrollEdgeAppearance = appearance
        applyNotesAccentToBarSymbols()
    }
}
