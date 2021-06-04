//
//  OfflineViewController.swift
//  EmbedFramework
//
//  Created by Aaron Vegh on 2019-06-06.
//  Copyright © 2019 Ada Support. All rights reserved.
//

import UIKit

class OfflineViewController: UIViewController {
    
    @IBOutlet var container: UIView!
    @IBOutlet var retryButton: UIButton!
    
    var retryBlock: (() -> Void)?
    
    static func create() -> OfflineViewController? {
        let bundle = Bundle(for: OfflineViewController.self)
        let frameworkBundlePath = bundle.path(forResource: "AdaEmbedFramework", ofType: "bundle")!
        let frameworkBundle = Bundle(path: frameworkBundlePath)
        let storyboard = UIStoryboard(name: "AdaWebHostViewController", bundle: frameworkBundle)
        return storyboard.instantiateViewController(withIdentifier: "OfflineViewController") as? OfflineViewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        retryButton.layer.cornerRadius = 6
    }
    
    @IBAction func retryNetworkConnection(sender: UIButton) {
        retryBlock?()
    }
    
}
