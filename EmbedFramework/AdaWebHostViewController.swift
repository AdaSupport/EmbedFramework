//
//  AdaWebHostViewController.swift
//  EmbedFramework
//
//  Created by Aaron Vegh on 2019-05-17.
//  Copyright © 2019 Ada Support. All rights reserved.
//

import UIKit
import WebKit

class AdaWebHostViewController: UIViewController {

    static func createWebController(with webView: WKWebView, adaWebHost: AdaWebHost) -> AdaWebHostViewController {
        let bundle = Bundle(for: AdaWebHostViewController.self)
        let storyboard = UIStoryboard(name: "AdaWebHostViewController", bundle: bundle)
        guard let viewController = storyboard.instantiateInitialViewController() as? AdaWebHostViewController else { fatalError("This should never, ever happen.") }
        viewController.webView = webView
        viewController.adaWebHost = adaWebHost
        return viewController
    }
    
    static func createNavController(with webView: WKWebView, adaWebHost: AdaWebHost) -> UINavigationController {
        let adaWebHostController = createWebController(with: webView, adaWebHost: adaWebHost)
        let navController = UINavigationController(rootViewController: adaWebHostController)
        
        let doneBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: adaWebHostController, action: #selector(doneButtonTapped(_:)))
        adaWebHostController.navigationItem.setLeftBarButton(doneBarButtonItem, animated: false)
        
        return navController
    }
    
    var webView: WKWebView?
    weak var adaWebHost: AdaWebHost?
    
    override func loadView() {
        super.loadView()
        view = webView
    }
    
    @objc func doneButtonTapped(_ sender: UIBarButtonItem) {
        adaWebHost?.teardownWebView()
        self.dismiss(animated: true, completion: nil)
    }
}
