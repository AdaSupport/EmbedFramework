//
//  ViewController.swift
//  ExampleApp
//
//  Created by Aaron Vegh on 2019-05-14.
//  Copyright © 2019 Aaron Vegh. All rights reserved.
//

import UIKit
import AdaEmbedFramework

class ViewController: UIViewController {
    
    lazy var adaFramework = AdaWebHost(handle: "nic", appScheme: "adaexampleapp")
        
    
    @IBOutlet var firstNameField: UITextField!
    @IBOutlet var lastNameField: UITextField!
    @IBOutlet var emailField: UITextField!

    @IBAction func submitForm(_ sender: UIButton) {
        guard
            let firstName = firstNameField.text,
            let lastName = lastNameField.text,
            let email = emailField.text else { return }
        
        adaFramework.setMetaFields([
            "firstName": firstName,
            "lastName": lastName,
            "email": email])
    }
    
    @IBAction func openModalSupport(_ sender: UIButton) {
        adaFramework.launchModalWebSupport(from: self)
    }
    
    @IBAction func openNavigationControllerSupport(_ sender: UIButton) {
        guard let navigationController = navigationController else { return }
        adaFramework.launchNavWebSupport(from: navigationController)
    }
    
    @IBAction func resetChat(_ sender: UIButton) {
        adaFramework.reset()
    }
    
    @IBAction func deleteHistory(_ sender: UIButton) {
        adaFramework.deleteHistory()
    }
    
    @IBAction func deleteListeners(_ sender: UIButton) {
        adaFramework.destroyListeners()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "injectingViewIdentifier",
              let injectingVC = segue.destination as? InjectedViewController else { return }
        _ = injectingVC.view
        adaFramework.launchInjectingWebSupport(into: injectingVC.injectingView)
    }
}
