import UIKit

protocol TaskSplitNavigating: AnyObject {
    func showSidebarColumn()
    func hideSidebarColumn()
    func didHideSidebar()
    func didSelectBoard(_ board: Board)
    func didUpdateBoard(_ board: Board)
    func makeAddMenu() -> UIMenu
    func showTaskDetail(_ controller: UIViewController)
    func hideTaskDetail()
    func allBoards() -> [Board]
    func addTask(_ task: BoardTask, toBoardID boardID: String)
}

final class AppRootViewController: UISplitViewController, UISplitViewControllerDelegate, TaskSplitNavigating {
    private let sidebarController = SidebarViewController()
    private let canvasController = CanvasViewController()
    private var sidebarHidden = false

    private lazy var sidebarNav = UINavigationController(rootViewController: sidebarController)
    private lazy var canvasNav = UINavigationController(rootViewController: canvasController)

    /// iPhone: свой главный экран вместо сайдбара, доски открываются push-переходом
    private let phoneHome = PhoneHomeViewController()
    private lazy var phoneNav = UINavigationController(rootViewController: phoneHome)
    private weak var phoneCanvas: CanvasViewController?

    init() {
        super.init(style: .doubleColumn)
        sidebarController.navigator = self
        canvasController.navigator = self
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        preferredPrimaryColumnWidth = 320
        minimumPrimaryColumnWidth = 300
        maximumPrimaryColumnWidth = 380
        presentsWithGesture = true
        displayModeButtonVisibility = .never
        setViewController(sidebarNav, for: .primary)
        setViewController(canvasNav, for: .secondary)
        configurePhoneHome()
        setViewController(phoneNav, for: .compact)
        applyNotesAccentToBars()
    }

    private func configurePhoneHome() {
        phoneHome.boards = { [weak self] in self?.sidebarController.allBoards() ?? [] }
        phoneHome.smartCards = { [weak self] in self?.sidebarController.smartCardsForDisplay() ?? [] }
        phoneHome.makeAddMenu = { [weak self] in self?.sidebarController.makeAddMenu() ?? UIMenu() }
        phoneHome.onSelectBoard = { [weak self] board in self?.pushPhoneCanvas(board) }
        phoneHome.onDeleteBoard = { [weak self] id in self?.sidebarController.removeBoard(id: id) }
        phoneHome.onMoveBoard = { [weak self] from, to in self?.sidebarController.moveBoard(from: from, to: to) }
        phoneHome.onToggleSmartCard = { [weak self] id, visible in self?.sidebarController.setSmartCard(id: id, visible: visible) }
        phoneHome.onMoveSmartCard = { [weak self] from, to in self?.sidebarController.moveSmartCard(from: from, to: to) }
        phoneNav.view.tintColor = .notesAccent
        phoneNav.navigationBar.applyNotesAccentAppearance()
    }

    private func pushPhoneCanvas(_ board: Board) {
        let canvas = CanvasViewController()
        canvas.navigator = self
        canvas.prefersTitleInBar = true
        canvas.loadViewIfNeeded()
        canvas.display(board: board)
        phoneCanvas = canvas
        phoneNav.pushViewController(canvas, animated: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyNotesAccentToBars()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        if !isCanvasPreview {
            layoutPrimaryColumnBelowStatusBar()
        }
        updateSidebarToggleForCurrentLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyNotesAccentToBars()
    }

    // Навбар доски переключается внутри системной анимации колонки (её transitionCoordinator)
    func didHideSidebar() {
        sidebarHidden = true
        canvasController.setSidebarToggleVisible(true, alongside: transitionCoordinator)
    }

    func showSidebarColumn() {
        sidebarHidden = false
        show(.primary)
        preferredDisplayMode = .oneBesideSecondary
        canvasController.setSidebarToggleVisible(false, alongside: transitionCoordinator)
    }

    func hideSidebarColumn() {
        sidebarHidden = true
        hide(.primary)
        canvasController.setSidebarToggleVisible(true, alongside: transitionCoordinator)
    }

    func didSelectBoard(_ board: Board) {
        canvasController.display(board: board)
        if isCollapsed {
            phoneHome.reload()
            pushPhoneCanvas(board)
        } else {
            show(.secondary)
        }
    }

    func didUpdateBoard(_ board: Board) {
        sidebarController.updateBoard(board)
        phoneHome.reload()
    }

    func makeAddMenu() -> UIMenu {
        sidebarController.makeAddMenu()
    }

    // MARK: - Задача в колонке-инспекторе справа

    private lazy var inspectorNav: UINavigationController = {
        let nav = UINavigationController()
        nav.view.tintColor = .notesAccent
        nav.navigationBar.applyNotesAccentAppearance()
        // Тонкий разделитель между доской и инспектором, как в «Почте»
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.isUserInteractionEnabled = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        nav.view.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: nav.view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: nav.view.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: nav.view.leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        return nav
    }()

    func showTaskDetail(_ controller: UIViewController) {
        // iPhone: карточка задачи — нативным листом снизу
        if isCollapsed {
            let sheet = UINavigationController(rootViewController: controller)
            sheet.view.tintColor = DetailTheme.accent
            sheet.navigationBar.applyNotesAccentAppearance()
            sheet.sheetPresentationController?.detents = [.medium(), .large()]
            sheet.sheetPresentationController?.prefersGrabberVisible = true
            (presentedViewController ?? self).present(sheet, animated: true)
            return
        }
        inspectorNav.setViewControllers([controller], animated: false)
        if viewController(for: .inspector) == nil {
            minimumInspectorColumnWidth = 440
            maximumInspectorColumnWidth = 540
            preferredInspectorColumnWidth = 480
            setViewController(inspectorNav, for: .inspector)
        }
        show(.inspector)
    }

    func hideTaskDetail() {
        if isCollapsed {
            presentedViewController?.dismiss(animated: true)
            return
        }
        hide(.inspector)
    }

    func allBoards() -> [Board] {
        sidebarController.allBoards()
    }

    func addTask(_ task: BoardTask, toBoardID boardID: String) {
        sidebarController.addTask(task, toBoardID: boardID)
    }

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        .primary
    }

    func splitViewController(_ svc: UISplitViewController, willHide column: UISplitViewController.Column) {
        guard column == .primary else { return }
        sidebarHidden = true
        canvasController.setSidebarToggleVisible(true, alongside: svc.transitionCoordinator)
    }

    func splitViewController(_ svc: UISplitViewController, willShow column: UISplitViewController.Column) {
        guard column == .primary else { return }
        sidebarHidden = false
        canvasController.setSidebarToggleVisible(false, alongside: svc.transitionCoordinator)
    }

    private func updateSidebarToggleForCurrentLayout() {
        // Во время анимации колонки состояние ведёт transitionCoordinator
        guard transitionCoordinator == nil else { return }
        canvasController.setSidebarToggleVisible(sidebarHidden, alongside: nil)
    }

    private var isCanvasPreview: Bool {
        var controller: UIViewController? = parent
        while let current = controller {
            if NSStringFromClass(type(of: current)).contains("StatusBarHostingController") {
                return true
            }
            controller = current.parent
        }
        return false
    }

    private func applyNotesAccentToBars() {
        view.tintColor = .notesAccent
        sidebarNav.toolbar.tintColor = .notesAccent
        sidebarNav.navigationBar.applyNotesAccentAppearance()
        canvasNav.toolbar.tintColor = .notesAccent
        canvasNav.navigationBar.applyNotesAccentAppearance(showsInlineTitle: true)
    }

    private func layoutPrimaryColumnBelowStatusBar() {
        guard !isCollapsed,
              !sidebarHidden,
              let primary = viewController(for: .primary)?.view,
              let superview = primary.superview,
              primary.window != nil
        else { return }

        var topInSplit = view.safeAreaInsets.top
        if let window = view.window {
            topInSplit = max(topInSplit, view.convert(CGPoint(x: 0, y: window.safeAreaInsets.top), from: window).y)
        }
        if canvasNav.isViewLoaded, canvasNav.navigationBar.window != nil {
            let barTop = canvasNav.navigationBar.convert(canvasNav.navigationBar.bounds, to: view).minY
            if barTop > 0.5 {
                topInSplit = max(topInSplit, barTop)
            }
        }

        let topInSuperview = view.convert(CGPoint(x: 0, y: topInSplit), to: superview).y
        let bottomInSuperview = view.convert(
            CGPoint(x: 0, y: view.bounds.height - view.safeAreaInsets.bottom),
            to: superview
        ).y

        var frame = primary.frame
        frame.origin.y = topInSuperview
        frame.size.height = max(bottomInSuperview - topInSuperview, 0)
        if abs(primary.frame.minY - frame.minY) > 0.5 || abs(primary.frame.height - frame.height) > 0.5 {
            primary.frame = frame
        }
        primary.clipsToBounds = true
    }
}
