//
//  HomeViewController.swift
//  VisualMatic_Example
//
//  Created by Indrajeet Senger on 05/05/21.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import VisualMatic

class HomeViewController: UIViewController {


    override func viewDidLoad() {
        super.viewDidLoad()
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    @IBAction func btnOpenCamera(sender: UIButton){
        let bundle = Bundle(for: CameraViewController.self)
        let storyboard = UIStoryboard(name: "Main_Framework", bundle: bundle)
        let controller = storyboard.instantiateViewController(withIdentifier: "CameraViewController") as! CameraViewController
        controller.delegate = self
        self.present(controller, animated: true, completion: nil)
    }
}

extension HomeViewController: CameraViewControllerDelegate {
    func closeButtonAction() {
        self.navigationController?.popViewController(animated: true)
    }
}
