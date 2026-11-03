import UIKit

/// UIKit text input must never borrow the document's undo manager through its
/// presenting responder chain. Cancel and reopening must preserve document redo.
@MainActor
private final class DraftSourceTextView: UITextView {
    private let draftUndoManager = UndoManager()
    override var undoManager: UndoManager? { draftUndoManager }
}

/// Draft changes stay in this sheet until Save; the caller commits one undo step.
@MainActor
final class ObjectSourceEditor: UIViewController, UITextViewDelegate {
    private let sourceView = DraftSourceTextView()
    private let preview = RichObjectView()
    private let message = UILabel()
    private let object: DocumentObject
    private let onSave: (String) -> Void
    private var previewTask: Task<Void, Never>?
    private var previewHeight: NSLayoutConstraint!

    init(object: DocumentObject, onSave: @escaping (String) -> Void) {
        self.object = object
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit source"
        isModalInPresentation = true
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .prominent, target: self, action: #selector(save))
        sourceView.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        sourceView.text = object.source
        sourceView.accessibilityLabel = "Object source"
        sourceView.accessibilityIdentifier = "object-source"
        sourceView.autocorrectionType = .no
        sourceView.smartQuotesType = .no
        sourceView.smartDashesType = .no
        sourceView.delegate = self
        sourceView.layer.borderWidth = 1
        sourceView.layer.borderColor = UIColor.separator.cgColor
        let caption = UILabel()
        caption.text = "Live preview"
        caption.font = .preferredFont(forTextStyle: .headline)
        message.font = .preferredFont(forTextStyle: .caption1)
        message.numberOfLines = 0
        let scroll = UIScrollView()
        scroll.backgroundColor = .white
        scroll.addSubview(preview)
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewHeight = preview.heightAnchor.constraint(equalToConstant: 80)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            preview.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            preview.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            preview.widthAnchor.constraint(equalToConstant: min(2_048, max(8, object.frame.width))), previewHeight
        ])
        let stack = UIStackView(arrangedSubviews: [sourceView, caption, scroll, message])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            sourceView.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            sourceView.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        preferredContentSize = CGSize(width: 700, height: 720)
        updatePreview()
    }

    func textViewDidChange(_ textView: UITextView) {
        navigationItem.rightBarButtonItem?.isEnabled = textView.text.utf8.count <= DocumentLimits.maxSourceBytes
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.updatePreview()
        }
    }
    private func updatePreview() {
        let source = sourceView.text ?? ""
        let width = min(2_048, max(8, object.frame.width))
        previewHeight.constant = RichTextRenderer.height(source: source, type: object.type, width: width)
        preview.frame.size = CGSize(width: width, height: previewHeight.constant)
        preview.configure(source: source, type: object.type, density: view.window?.screen.scale ?? 2)
        message.text = source.utf8.count > DocumentLimits.maxSourceBytes ? "Source exceeds the 100 KB object limit." :
            preview.hasWarning ? "Rendering warning. The source will be saved unchanged." : "Save updates this object. Cancel discards this draft."
    }
    @objc private func cancel() { previewTask?.cancel(); dismiss(animated: true) }
    @objc private func save() {
        guard sourceView.text.utf8.count <= DocumentLimits.maxSourceBytes else { return }
        previewTask?.cancel()
        onSave(sourceView.text)
        dismiss(animated: true)
    }
}
