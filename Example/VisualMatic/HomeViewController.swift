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

    @IBOutlet weak var btnScanOutlet: UIButton!
    @IBOutlet weak var lblProgressPercent: UILabel!
    @IBOutlet weak var progressView: UIProgressView!

    let progress = Progress(totalUnitCount: 100)

    override func viewDidLoad() {
        super.viewDidLoad()
        progressView.progress = 0.0
        progress.completedUnitCount = 0

        manageControlVisibility(isModelLoaded: false)
        VMAPIService.sharedVMAPIService.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        VMAPIService.sharedVMAPIService.loadMLModel()
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    @IBAction func btnScan(sender: UIButton){
        let bundle = Bundle(for: CameraViewController.self)
        let storyboard = UIStoryboard(name: "Main_Framework", bundle: bundle)
        let controller = storyboard.instantiateViewController(withIdentifier: "CameraViewController") as! CameraViewController
        controller.delegate = self
        controller.EnableTabBar = true
        self.present(controller, animated: true, completion: nil)
    }
    
//    @IBAction func btnRecogniseText(sender: UIButton){
//        openCamera(type: .TextRecognizer)
//    }
//
//    @IBAction func btnScanBarcode(sender: UIButton) {
//        openCamera(type: .BarcodeScanner)
//    }
    
    private func openCamera(type: ScannerType){
    }
    
    private func manageControlVisibility(isModelLoaded: Bool) {
        btnScanOutlet.isEnabled = isModelLoaded
        progressView.isHidden = isModelLoaded
        lblProgressPercent.isHidden = isModelLoaded
    }
}

//MARK:- CameraViewControllerDelegate methods
extension HomeViewController: CameraViewControllerDelegate {
    func closeButtonAction() {
        self.dismiss(animated: true, completion: nil)
    }
}

//MARK:- VMAPIServiceDelegate methods
extension HomeViewController: VMAPIServiceDelegate {
    func downloadError(error: Error) {
        print(error)
    }
    
    func downloadProgress(downloadPercent: Int64) {        
        if (downloadPercent == 100) {
            lblProgressPercent.text = "Model Downloaded."
            manageControlVisibility(isModelLoaded: true)
        } else {
            progress.completedUnitCount = downloadPercent
            self.progressView.setProgress(Float(progress.fractionCompleted), animated: true)
            lblProgressPercent.text = "Downloading \(downloadPercent) %"
        }
    }
    
    func downloadCompleted() {
        DispatchQueue.main.async {
            self.manageControlVisibility(isModelLoaded: true)
        }
    }
}
