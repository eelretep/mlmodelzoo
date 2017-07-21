//
//  ViewController.swift
//  SimpleSample
//
//  Created by Peter Lee on 7/18/17.
//  Copyright © 2017 MLModelZoo. All rights reserved.
//

import UIKit
import Vision

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    
    var visionCoreMLModel: VNCoreMLModel!
    var visionCoreMLRequest: VNCoreMLRequest!
    let modelzoo = mlmodelzoo()
    
    var inputImage: UIImage?
    var outputImage: UIImage?
    
    // MARK: - lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            visionCoreMLModel = try VNCoreMLModel(for: modelzoo.model)
            visionCoreMLRequest = VNCoreMLRequest(model: visionCoreMLModel, completionHandler: handleVisionMLRequest)
            visionCoreMLRequest.imageCropAndScaleOption = .scaleFill
        } catch {
            fatalError("cannot load model:\(error)")
        }
    }

    // MARK: - user interface
    @IBAction func getInputTapped(_ sender: Any) {
        clearImageView()
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (action) in
            self.showPicker(source: .camera)
        }))
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { (action) in
            self.showPicker(source: .photoLibrary)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
        }))
        
        present(alert, animated: true) {
        }
    }
    
    @IBAction func imageTapped(_ sender: Any) {
        if inputImage != nil && outputImage != nil {
            if imageView.image == inputImage {
                updateImageView(image: outputImage!)
            } else if imageView.image == outputImage {
                updateImageView(image: inputImage!)
            }
        }
    }
    
    func showPicker(source: UIImagePickerControllerSourceType) {
        updateLabel(status: "loading picker...")
        
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self

        self.present(picker, animated: true) {
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        updateLabel(status: nil)
        
        if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
            
            inputImage = image
            outputImage = nil
            updateImageView(image: image)
            
            sendRequestToModel(image: image)
        }
        
        self.dismiss(animated: true) {
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        updateLabel(status: nil)
        
        self.dismiss(animated: true) {
        }
    }
    
    // MARK: - model inference
    func sendRequestToModel(image: UIImage) {
        updateLabel(status: "sent request to model")

#if !USE_COREML_STYLER
          let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!, orientation: image.cgImagePropertyOrientation(), options:[:])
    
        DispatchQueue.global(qos: .userInitiated).async { // avoid blocking the main thread
            do {
                try requestHandler.perform([self.visionCoreMLRequest])
            } catch {
                print(error)
                self.updateLabel(status: error.localizedDescription)
            }
        }
#else //iOS11 beta3 - CoreML workaround for internal Vision bug when resizing images to fit model input dimensions
        let inputWidth = 480
        let inputHeight = 640
    
        DispatchQueue.global(qos: .userInitiated).async { // avoid blocking the main thread
            do {
                let inPixelBuffer = CGImageToPixelBufferRGB(image.cgImage!, width: inputWidth, height: inputHeight)!
                let outPixelBuffer = try self.modelzoo.prediction(input: mlmodelzooInput(input1: inPixelBuffer)).output1
                self.updateOutputWithPixelBuffer(outPixelBuffer, width: Int(image.size.width), height: Int(image.size.height), orientation: image.imageOrientation)
            } catch {
                print(error)
                self.updateLabel(status: error.localizedDescription)
            }
        }
#endif
    }
    
    func handleVisionMLRequest(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNClassificationObservation] {
            handleClassificationObservations(observations)
            
        } else {
            print("unexpected result type")
            return
        }
    }
    
    func handleClassificationObservations(_ observations: [VNClassificationObservation]) {
        var textLabels = [String]()
        for observation in observations {
            if observation.confidence > 0.1 { // confidence threshold
                textLabels.append("\(observation.identifier) \(observation.confidence)")
            }
        }
        
        self.updateLabel(status: textLabels.joined(separator: "\n"))
    }

    // MARK: - result visualization
    func updateOutputWithPixelBuffer(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int, orientation: UIImageOrientation) {
        updateLabel(status: "showing results")
        
        if let image = pixelBufferBGRToImage(pixelBuffer, width:width, height:height, orientation: orientation) {
            outputImage = image
            updateImageView(image: image)
        }
    }
    
    func clearImageView() {
        imageView.image = nil
        statusLabel.text = nil
    }
    
    func updateImageView(image: UIImage) {
        DispatchQueue.main.async {
            UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                self.imageView.image = image
            }, completion: nil)
        }
    }
    
    func updateLabel(status: String?) {
        DispatchQueue.main.async {
            self.statusLabel.text = status
        }
    }
}

