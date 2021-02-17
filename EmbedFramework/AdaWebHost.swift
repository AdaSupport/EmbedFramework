//
//  AdaWebHost.swift
//  AdaSDK
//
//  Created by Aaron Vegh on 2019-05-14.
//  Copyright © 2019 Aaron Vegh. All rights reserved.
//

import Foundation
import WebKit
import SafariServices

public class AdaWebHost: NSObject {
    
    public var handle = ""
    public var cluster = ""
    public var language = ""
    public var styles = ""
    public var greeting = ""
    
    /// Metafields can be passed in during init; use `setMetaFields()`
    /// to send values in at runtime
    private var metafields: [String: String] = [:]
    
    public var openWebLinksInSafari = false
    public var appScheme = ""
    
    public var zdChatterAuthCallback: (((@escaping (_ token: String) -> Void)) -> Void)?
    public var eventCallbacks: [String: (_ event: [String: Any]) -> Void]?
    
    /// Here's where we do our business
    private var webView: WKWebView?
    
    /// Key an eye on the network
    private let reachability: Reachability
    
    /// Keep a reference to the OfflineViewController
    private var offlineViewController: OfflineViewController?
    
    /// Keep track of whether the host is loaded
    private var webHostLoaded = false {
        didSet {
            if webHostLoaded == true {
                self.initializeWebView()
                for command in pendingCommands {
                    self.evalJS(command)
                }
            }
        }
    }
    
    /// Keep track of whether we're showing offline view
    internal var isInOfflineMode = false
    
    /// If commands are sent prior to `embedReady`, store until it can be cleared out
    private var pendingCommands = [String]()
    
    private lazy var scriptSource: String = {
        do {
            let bundle = Bundle(for: AdaWebHost.self)
            guard let sourcePath = bundle.path(forResource: "AdaEmbed", ofType: "html") else { return "" }
            return try String(contentsOfFile: sourcePath)
        } catch {
            return ""
        }
    }()
    
    public init(
        handle: String,
        cluster: String = "",
        language: String = "",
        styles: String = "",
        greeting: String = "",
        metafields: [String: String] = [:],
        openWebLinksInSafari: Bool = false,
        appScheme: String = "",
        zdChatterAuthCallback: (((@escaping (_ token: String) -> Void)) -> Void)? = nil,
        eventCallbacks: [String: (_ event: [String: Any]) -> Void]? = nil
    ) {
        self.handle = handle
        self.cluster = cluster
        self.language = language
        self.styles = styles
        self.greeting = greeting
        self.metafields = metafields
        self.openWebLinksInSafari = openWebLinksInSafari
        self.appScheme = appScheme
        self.zdChatterAuthCallback = zdChatterAuthCallback
        self.eventCallbacks = eventCallbacks
    
        self.reachability = Reachability()!
        super.init()
        
        reachability.whenReachable = { _ in
            self.isInOfflineMode = false
        }
        
        reachability.whenUnreachable = { [weak self] _ in
            guard let strongSelf = self,
                  let webView = strongSelf.webView else { return }
            
            strongSelf.isInOfflineMode = true
            
            if webView.superview != nil {
                strongSelf.offlineViewController = OfflineViewController.create()
                if let offlineVC = strongSelf.offlineViewController {
                    offlineVC.retryBlock = {
                        strongSelf.returnToOnline()
                    }
                    offlineVC.view.translatesAutoresizingMaskIntoConstraints = false
                    webView.addSubview(offlineVC.view)
                    NSLayoutConstraint.activate([
                        offlineVC.view.topAnchor.constraint(equalTo: webView.topAnchor),
                        offlineVC.view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                        offlineVC.view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                        offlineVC.view.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
                    ])
                }
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(AdaWebHost.keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        do {
            try reachability.startNotifier()
        } catch {
            print("Unable to start reachability notifier.")
        }
        
        setupWebView()
    }
    
    // MARK: - Public Methods
    
    /// Push a dictionary of fields to the server
    public func setMetaFields(_ fields: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: fields, options: .fragmentsAllowed),
            let jsonString = String(data: json, encoding: .utf8) else { return }
        let toRun = "adaEmbed.setMetaFields(\(jsonString));"
        
        self.evalJS(toRun)
    }
    
    /// Re-initialize chat and optionally reset history, language, meta data, etc
    public func reset(language: String? = nil, greeting: String? = nil, metaFields: [String: Any]? = nil, resetChatHistory: Bool? = true) {
        
        let data: [String: Any?] = [
            "language": language,
            "greeting": greeting,
            "metaFields": metaFields,
            "resetChatHistory": resetChatHistory
        ]
        
        guard let json = try? JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed),
              let jsonString = String(data: json, encoding: .utf8) else { return }
        let toRun = "adaEmbed.reset(\(jsonString));"
        
        self.evalJS(toRun)
    }
    
    /// Re-initialize chat and optionally reset history, language, meta data, etc
    public func deleteHistory() {
        let toRun = "adaEmbed.deleteHistory();"
        
        self.evalJS(toRun)
    }
    
    /// Provide a view controller to launch web support from
    /// this will present the chat view modally
    public func launchModalWebSupport(from viewController: UIViewController) {
        guard let webView = webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = true
        let webNavController = AdaWebHostViewController.createNavController(with: webView)
        webNavController.modalPresentationStyle = .overFullScreen
        viewController.present(webNavController, animated: true, completion: nil)
    }
    
    /// Provide a navigation controller to push web support onto the stack
    public func launchNavWebSupport(from navController: UINavigationController) {
        guard let webView = webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = true
        let webController = AdaWebHostViewController.createWebController(with: webView)
        navController.pushViewController(webController, animated: true)
    }
    
    /// Provide a view to inject the web support into
    public func launchInjectingWebSupport(into view: UIView) {
        guard let webView = webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: webView.topAnchor),
            view.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
        ])
    }
}

extension AdaWebHost {
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        configuration.userContentController = userContentController
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        guard let webView = webView else { return }
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        webView.loadHTMLString(scriptSource, baseURL: nil)
        
        // Bind handlers for JS messages
        userContentController.add(self, name: "embedReady")
        userContentController.add(self, name: "eventCallbackHandler")
        userContentController.add(self, name: "zdChatterAuthCallbackHandler")
    }
}

extension AdaWebHost: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
        let httpSchemes = ["http", "https"]
        
        if navigationAction.navigationType == WKNavigationType.linkActivated {
            if let url = navigationAction.request.url {
                let urlScheme = url.scheme
                // Handle opening universal links within the host App
                // This requires the appScheme argument to work
                if urlScheme == self.appScheme {
                    guard let presentingVC = findViewController(from: webView) else { return }
                    presentingVC.dismiss(animated: true) {
                        let shared = UIApplication.shared
                        if shared.canOpenURL(url) {
                            shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                // Only open links in in-app WebView if URL uses HTTP(S) scheme, and the openWebLinksInSafari option is false
                } else if self.openWebLinksInSafari == false && httpSchemes.contains(urlScheme ?? "") {
                    let sfVC = SFSafariViewController(url: url)
                    guard let presentingVC = findViewController(from: webView) else { return }
                    presentingVC.present(sfVC, animated: true, completion: nil)
                } else {
                    let shared = UIApplication.shared
                    if shared.canOpenURL(url) {
                        shared.open(url, options: [:], completionHandler: nil)
                    }
                }
            }
            decisionHandler(.cancel)
        }
        else {
            decisionHandler(.allow)
        }
    }
}

extension AdaWebHost: WKScriptMessageHandler {
    /// When the webview loads up, it'll pass back a message to here.
    /// Fire our initialize methods when that happens.
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let messageName = message.name
        
        if messageName == "embedReady" {
            self.webHostLoaded = true
        } else if let zdChatterAuthCallback = self.zdChatterAuthCallback, messageName == "zdChatterAuthCallbackHandler" {
            zdChatterAuthCallback() { token in
                self.evalJS("window.zdTokenCallback(\"\(token)\");")
            }
        } else if messageName == "eventCallbackHandler" {
            if let event = message.body as? [String: Any] {
                if let eventName = event["event_name"] as? String {
                    if let specificCallback = self.eventCallbacks?[eventName] {
                        specificCallback(event)
                    }
                }
                
                if let specificCallback = self.eventCallbacks?["*"] {
                    specificCallback(event)
                }
            }
        }
    }
}

extension AdaWebHost {
    private func initializeWebView() {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self.metafields, options: [])
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"

            evalJS("""
                (function() {
                    window.adaEmbed.start({
                        handle: "\(self.handle)",
                        cluster: "\(self.cluster)",
                        language: "\(self.language)",
                        styles: "\(self.styles)",
                        greeting: "\(self.greeting)",
                        metaFields: \(json),
                        parentElement: "parent-element",
                        zdChatterAuthCallback: function(callback) {
                            window.zdTokenCallback = callback;
                            window.webkit.messageHandlers.zdChatterAuthCallbackHandler.postMessage("getToken");
                        },
                        eventCallbacks: {
                            "*": (event) => window.webkit.messageHandlers.eventCallbackHandler.postMessage(event)
                        }
                    });
                })();
            """)
        } catch (let error) {
            print("Serialization error: \(error.localizedDescription)")
            return
        }
    }
    
    private func evalJS(_ toRun: String) {
        guard self.webHostLoaded else {
            pendingCommands.append(toRun)
            return
        }
        guard let webView = webView else { return }

        webView.evaluateJavaScript(toRun) { (result, error) in
            if let err = error {
                print(err)
            } else {
                guard let dataValue = result else { return }
                print(dataValue)
            }
        }
    }
    
    private func returnToOnline() {
        guard !isInOfflineMode else { return }
        
        if let offlineVC = self.offlineViewController {
            offlineVC.view.removeFromSuperview()
            self.offlineViewController = nil
        }
        
        // This should reset the webview if client is offline on launch
        if !self.webHostLoaded {
            self.setupWebView()
        }
    }
}

extension AdaWebHost {
    @objc func keyboardWillHide(notification: NSNotification) {
        if #available(iOS 12.0, *) {
            guard let webView = webView else { return }
            
            for view in webView.subviews {
                if view.isKind(of: NSClassFromString("WKScrollView") ?? UIScrollView.self) {
                    guard let scroller = view as? UIScrollView else { return }
                    scroller.contentOffset = CGPoint(x: 0, y: 0)
                }
            }
        }
    }
}

extension AdaWebHost {
    func findViewController(from view: UIView) -> UIViewController? {
        if let nextResponder = view.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = view.next as? UIView {
            return findViewController(from: nextResponder)
        } else {
            return nil
        }
    }
}
