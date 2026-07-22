//
//  ViewController.swift
//  CamsinkApp
//
//  가상 카메라 익스텐션을 설치하고 제거하는 것이 이 앱의 전부다.
//  프레임을 넣는 일은 camsink-feed 헬퍼가 맡는다.
//
//  익스텐션 활성화 방식은 ldenoue/cameraextension (MIT, © 2022 Laurent Denoue)
//  을 참고했다.
//

import Cocoa
import SystemExtensions

class ViewController: NSViewController {

    private var statusLabel: NSTextField!
    private var installButton: NSButton!
    private var removeButton: NSButton!

    // MARK: - 익스텐션 제어

    /// 앱 번들 안에 들어 있는 시스템 익스텐션을 찾는다.
    private static func extensionBundle() -> Bundle? {
        let directory = URL(fileURLWithPath: "Contents/Library/SystemExtensions",
                            relativeTo: Bundle.main.bundleURL)
        guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles),
              let first = urls.first else { return nil }
        return Bundle(url: first)
    }

    @objc private func install() {
        guard let identifier = Self.extensionBundle()?.bundleIdentifier else {
            show("앱 안에서 익스텐션을 찾지 못했습니다.")
            return
        }
        show("설치를 요청하는 중...")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    @objc private func remove() {
        guard let identifier = Self.extensionBundle()?.bundleIdentifier else { return }
        show("제거를 요청하는 중...")
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - 화면

    override func viewDidLoad() {
        super.viewDidLoad()

        let title = NSTextField(labelWithString: "camsink 가상 카메라")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        statusLabel = NSTextField(wrappingLabelWithString:
            "아래 '설치'를 누른 뒤 시스템 설정에서 확장 프로그램을 허용하세요.")
        statusLabel.textColor = .secondaryLabelColor

        installButton = NSButton(title: "설치", target: self, action: #selector(install))
        installButton.keyEquivalent = "\r"
        removeButton = NSButton(title: "제거", target: self, action: #selector(remove))

        let buttons = NSStackView(views: [installButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [title, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
    }

    private func show(_ text: String) {
        statusLabel.stringValue = text
    }
}

// MARK: - 설치 요청 결과

extension ViewController: OSSystemExtensionRequestDelegate {

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension new: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // 버전이 같아도 새로 빌드한 것으로 갈아끼운다. 개발 중에 이게 편하다.
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        show("시스템 설정 > 일반 > 로그인 항목 및 확장 > 카메라 확장 프로그램에서\n"
             + "camsink을 켜주세요.")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            show("완료됐습니다. 화상회의 앱의 카메라 목록에서 camsink을 고를 수 있습니다.")
        case .willCompleteAfterReboot:
            show("재시동 후에 적용됩니다.")
        @unknown default:
            show("알 수 없는 결과: \(result.rawValue)")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        show("실패했습니다: \(error.localizedDescription)")
    }
}
