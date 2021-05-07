//
//  ScannerViewController.swift
//  VisualMatic_Example
//
//  Created by Indrajeet Senger on 05/05/21.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import VisualMatic

class ScannerViewController: UIViewController {

//    @IBOutlet weak var vwCamera: UIView!
//    var vwCameraView: UIView
    
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
    
    @IBAction func btnBackAction(sender: UIButton){
        self.navigationController?.popViewController(animated: true)
    }

}
