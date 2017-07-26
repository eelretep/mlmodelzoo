//
//  ViewController.swift
//  SimpleSample
//
//  Created by Peter Lee on 7/18/17.
//  Copyright © 2017 MLModelZoo. All rights reserved.
//

import UIKit
import Vision
import AVFoundation

enum ModelInput {
    case unknown
    case photoLibrary
    case camera
    case video
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var overlayView: UIView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var visualizationView: VisualizationView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var statsLabel: UILabel!
    
    var visionCoreMLModel: VNCoreMLModel!
    var visionCoreMLRequest: VNCoreMLRequest!
    let modelzoo = mlmodelzoo()
    
    var inputImage: UIImage?
    var outputImage: UIImage?
    
    let capturePreset = AVCaptureSession.Preset.vga640x480
    let captureSettings: [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String : kCMPixelFormat_32BGRA]
    var session: AVCaptureSession!
    var videoDataOutput: AVCaptureVideoDataOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    let sampleDispatchQueue = DispatchQueue(label: "SampleDispatch")
    let mlProcessingSlots = DispatchSemaphore(value: 1) // throttle the model processing
    var processedSampleTimes = [Date]()
    
    var modelInput = ModelInput.unknown {
        didSet {
            clearOverlay()
            
            if modelInput == .video {
                setupAVSourceCapture()
                session.startRunning()
                self.overlayView.backgroundColor = UIColor.clear
            } else {
                self.session?.stopRunning()
                self.overlayView.backgroundColor = UIColor.white
            }
        }
    }
    
    // MARK: - lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            visionCoreMLModel = try VNCoreMLModel(for: modelzoo.model)
            visionCoreMLRequest = VNCoreMLRequest(model: visionCoreMLModel, completionHandler: handleVisionMLRequest)
            visionCoreMLRequest.imageCropAndScaleOption = .scaleFill
            
            Timer.scheduledTimer(withTimeInterval:0.25, repeats: true) {_ in
                self.updateOnTimer()
            }
        } catch {
            fatalError("cannot load model:\(error)")
        }
    }
    
    // MARK: - video capture
    func setupAVSourceCapture()
    {
        if session?.isRunning == true {
            return
        }
        
        session = AVCaptureSession()
        session.sessionPreset = capturePreset
        
        let device = AVCaptureDevice.default(for: .video)
        guard let deviceInput = try? AVCaptureDeviceInput(device: device!) else
        {
            fatalError()
        }
        
        if session.canAddInput(deviceInput)
        {
            session.addInput(deviceInput)
        }
        
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = captureSettings
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue:sampleDispatchQueue)
        
        if session.canAddOutput(videoDataOutput!)
        {
            session.addOutput(videoDataOutput!)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.backgroundColor = UIColor.black.cgColor
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.frame = videoView.bounds
        
        previewLayer.connection?.videoOrientation = .portrait
        videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
        
        videoView.layer.addSublayer(previewLayer!)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        
        self.sendRequestToModel(image: nil, orPixelBuffer: pixelBuffer, skipIfBusy: true)
    }

    // MARK: - user interface
    @IBAction func getInputTapped(_ sender: Any) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Pick photo", style: .default, handler: { (action) in
            self.modelInput = .photoLibrary
            self.showPicker(source: .photoLibrary)
        }))
        alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { (action) in
            self.modelInput = .camera
            self.showPicker(source: .camera)
        }))
        alert.addAction(UIAlertAction(title: "Live video", style: .default, handler: { (action) in
            self.modelInput = .video
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
            updateImageView(image: image)
            
            sampleDispatchQueue.async {
                self.sendRequestToModel(image: image)
            }
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
    func sendRequestToModel(image: UIImage?, orPixelBuffer pixelBuffer:CVPixelBuffer? = nil, skipIfBusy: Bool = false) {
        assert (image != nil || pixelBuffer != nil)
        dispatchPrecondition(condition: .onQueue(sampleDispatchQueue))
        
        if mlProcessingSlots.wait(timeout:DispatchTime.now()) != .success {
            if skipIfBusy {
                return
            } else {
                // blocking wait
                let result = self.mlProcessingSlots.wait(timeout:DispatchTime.distantFuture)
                assert (result == .success)
            }
        }
        processedSampleTimes.append(Date())
        processedSampleTimes.removeFirst(max(0,processedSampleTimes.count-10))
        
#if !USE_COREML_STYLER
    let requestHandler = image != nil ? VNImageRequestHandler(cgImage: image!.cgImage!, orientation: image!.cgImagePropertyOrientation(), options:[:]) :
        VNImageRequestHandler(cvPixelBuffer: pixelBuffer!, options: [:])
    
        DispatchQueue.global(qos: .userInitiated).async { // avoid blocking the queue
            do {
                try requestHandler.perform([self.visionCoreMLRequest])
                self.mlProcessingSlots.signal()
            } catch {
                print(error)
                self.updateLabel(status: error.localizedDescription)
                self.mlProcessingSlots.signal()
            }
        }
#else //iOS11 beta3 - CoreML workaround for internal Vision bug when resizing images to fit model input dimensions
        let inputWidth = 480
        let inputHeight = 640
    
        DispatchQueue.global(qos: .userInitiated).async { // avoid blocking the queue
            do {
                if let image = image {
                    let inPixelBuffer = CGImageToPixelBufferRGB(image.cgImage!, width: inputWidth, height: inputHeight)!
                    let outPixelBuffer = try self.modelzoo.prediction(input: mlmodelzooInput(input1: inPixelBuffer)).output1
                    self.updateOutputWithPixelBuffer(outPixelBuffer, width: Int(image.size.width), height: Int(image.size.height), orientation: image.imageOrientation)
                } else {
                    let outPixelBuffer = try self.modelzoo.prediction(input: mlmodelzooInput(input1: pixelBuffer!)).output1
                    self.updateOutputWithPixelBuffer(outPixelBuffer, width: inputWidth, height: inputHeight, orientation: UIImageOrientation.up)
                }
                self.mlProcessingSlots.signal()
            } catch {
                print(error)
                self.updateLabel(status: error.localizedDescription)
                self.mlProcessingSlots.signal()
            }
        }
#endif
    }
    
    func handleVisionMLRequest(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNClassificationObservation] {
            handleClassificationObservations(observations)
            
        } else if let observations = request.results as? [VNCoreMLFeatureValueObservation] {
            //TODO: need a better way of routing model postprocessing instead of assuming this is yolo tiny
            if let multiArray = observations.first?.featureValue.multiArrayValue {
                YoloTiny.postprocess(multiArray: multiArray, intoView: visualizationView)
            }
        } else {
            print("unexpected result type")
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
    
    func clearOverlay() {
        inputImage = nil
        outputImage = nil
        imageView.image = nil
        statusLabel.text = nil
        statsLabel.text = nil
        visualizationView.clearBoxes()
        processedSampleTimes.removeAll()
    }
    
    func updateImageView(image: UIImage?) {
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
    
    func updateOnTimer() {
        if self.modelInput == .video {
            self.visualizationView.decayStep()
            
            var fps = 0.0
            if let earliestSampleTime = processedSampleTimes.first {
                fps = Double(processedSampleTimes.count) / Date().timeIntervalSince(earliestSampleTime)
                statsLabel.text = String(format:"%.2f fps", fps)
            }
        }
    }
}

