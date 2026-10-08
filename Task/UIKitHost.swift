import SwiftUI
import UIKit

struct UIKitHost<Controller: UIViewController>: UIViewControllerRepresentable {
    let make: () -> Controller

    func makeUIViewController(context: Context) -> StatusBarHostingController<Controller> {
        StatusBarHostingController(child: make())
    }

    func updateUIViewController(_ uiViewController: StatusBarHostingController<Controller>, context: Context) {}
}

final class StatusBarHostingController<Controller: UIViewController>: UIViewController {
    let child: Controller

    init(child: Controller) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
    override var childForStatusBarHidden: UIViewController? { nil }
    override var childForStatusBarStyle: UIViewController? { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)
    }
}
