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
    
    /// Set the chat to open links in Safari
    /// Set to false to use SFSafariViewController instead
    public var openWebLinksInSafari = true
    
    /// If your app handles universal links, provide the scheme here, so the chat view will forward the link appropriately
    public var appScheme = ""
    
    /// Metafields can be passed in during init; use `setMetaFields()`
    /// to send values in at runtime
    private var metafields: [String: String]?
    
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
    
    public init(handle: String, openWebLinksInSafari: Bool, appScheme: String = "", cluster: String = "", language: String = "", styles: String = "", greeting: String = "", metafields: [String: String]? = [:]) {
        self.handle = handle
        self.appScheme = appScheme
        self.openWebLinksInSafari = openWebLinksInSafari
        self.cluster = cluster
        self.language = language
        self.styles = styles
        self.greeting = greeting
        self.metafields = metafields
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
        let serializedData = try! JSONSerialization.data(withJSONObject: fields, options: [])
        let encodedData = serializedData.base64EncodedString()
        let toRun = "setMetaFields('\(encodedData)');"
        
        self.evalJS(toRun)
    }
    
    /// Re-initialize chat and optionally reset history, language, meta data, etc
    public func reset(language: String? = nil, greeting: String? = nil, metaFields: [String: Any]? = nil, resetChatHistory: Bool? = nil) {
        
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
        let clusterString = cluster.isEmpty ? "" : "\(cluster)."
        configuration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        guard let webView = webView else { return }
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        

        guard let remoteURL = URL(string: "https://\(handle).\(clusterString)ada.support/mobile-sdk-webview/") else { return }
        let webRequest = URLRequest(url: remoteURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        webView.load(webRequest)
        userContentController.add(self, name: "embedReady")
    }
}

extension AdaWebHost: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Swift.Void) {
        if navigationAction.navigationType == WKNavigationType.linkActivated {
            if let url = navigationAction.request.url {
                if url.scheme == appScheme {
                    guard let presentingVC = findViewController(from: webView) else { return }
                    presentingVC.dismiss(animated: true) {
                        let shared = UIApplication.shared
                        if shared.canOpenURL(url) {
                            shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                } else if openWebLinksInSafari {
                    let shared = UIApplication.shared
                    if shared.canOpenURL(url) {
                        shared.open(url, options: [:], completionHandler: nil)
                    }
                } else {
                    let sfVC = SFSafariViewController(url: url)
                    guard let presentingVC = findViewController(from: webView) else { return }
                    presentingVC.present(sfVC, animated: true, completion: nil)
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
        print("PM: \(message.name), \(message.body) ")
        if message.name == "embedReady" {
            self.webHostLoaded = true
        }
    }
}

extension AdaWebHost {
    private func initializeWebView() {
        do {
            let dictionaryData = [
                "handle": self.handle,
                "cluster": self.cluster,
                "language": self.language,
                "styles": self.styles,
                "greeting": self.greeting
                ] as [String : Any]
            let serializedData = try JSONSerialization.data(withJSONObject: dictionaryData, options: [])
            let encodedData = serializedData.base64EncodedString()
            evalJS("initializeEmbed('\(encodedData)');")
            if let metafields = self.metafields {
                setMetaFields(metafields)
            }
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
        print("Running command: \(toRun)")
        webView.evaluateJavaScript(toRun) { (result, error) in
            if let err = error {
                print(err)
                print(err.localizedDescription)
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
