#if canImport(UIKit)
import NavigationStackController
import UIKit

@MainActor
final class DemoPageController: UIViewController {
    private let number: Int
    private var forwardButton: UIButton?

    init(number: Int) {
        self.number = number
        super.init(nibName: nil, bundle: nil)
        title = "Page \(number)"
    }

    required init?(coder: NSCoder) { nil }

    private var stackController: NavigationStackController? {
        navigationController as? NavigationStackController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = number.isMultiple(of: 2) ? .secondarySystemBackground : .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Next", image: UIImage(systemName: "plus"), target: self, action: #selector(openNextPage)
        )

        let titleLabel = UILabel()
        titleLabel.text = "Page \(number)"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityIdentifier = "pageTitle"

        let instructions = UILabel()
        instructions.text = "Swipe horizontally to go back or forward. A new page clears forward history."
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.adjustsFontForContentSizeCategory = true

        let next = makeButton("Open next page", identifier: "openNextPage", action: #selector(openNextPage))
        let forward = makeButton("Go forward", identifier: "goForward", action: #selector(goForward))
        forwardButton = forward

        let scrollLabel = UILabel()
        scrollLabel.text = "Horizontal content scrolls first; swipe at its boundary to navigate."
        scrollLabel.numberOfLines = 0
        scrollLabel.font = .preferredFont(forTextStyle: .footnote)
        scrollLabel.adjustsFontForContentSizeCategory = true

        let scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = "horizontalContent"
        let cards = UIStackView()
        cards.axis = .horizontal
        cards.spacing = 12
        for index in 1...3 {
            let card = UILabel()
            card.text = "Page \(number) · Card \(index)"
            card.textAlignment = .center
            card.font = .preferredFont(forTextStyle: .headline)
            card.backgroundColor = [UIColor.systemBlue, .systemGreen, .systemOrange][index - 1].withAlphaComponent(0.2)
            card.layer.cornerRadius = 12
            card.clipsToBounds = true
            card.widthAnchor.constraint(equalToConstant: 260).isActive = true
            cards.addArrangedSubview(card)
        }
        cards.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(cards)
        NSLayoutConstraint.activate([
            cards.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            cards.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            cards.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 140)
        ])

        let bar = makeButton("Toggle navigation bar", identifier: "toggleBar", action: #selector(toggleBar))
        let direction = makeButton("Toggle layout direction", identifier: "toggleDirection", action: #selector(toggleDirection))
        let content = UIStackView(arrangedSubviews: [titleLabel, instructions, next, forward, scrollLabel, scrollView, bar, direction])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        updateNavigationButtons()
    }

    func updateNavigationButtons() {
        forwardButton?.isEnabled = stackController?.canGoForward == true
    }

    private func makeButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openNextPage() {
        navigationController?.pushViewController(DemoPageController(number: number + 1), animated: true)
    }

    @objc private func goForward() {
        stackController?.goForward(animated: true)
    }

    @objc private func toggleBar() {
        guard let navigationController else { return }
        navigationController.setNavigationBarHidden(!navigationController.isNavigationBarHidden, animated: true)
    }

    @objc private func toggleDirection() {
        guard let navigationController else { return }
        navigationController.view.semanticContentAttribute =
            navigationController.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? .forceLeftToRight : .forceRightToLeft
    }
}
#endif
