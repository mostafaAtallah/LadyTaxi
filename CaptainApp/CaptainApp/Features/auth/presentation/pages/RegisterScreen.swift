import SwiftUI
import UIKit

struct RegisterScreen: View {
    
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var currentStep = 0
    
    // Personal Info
    @State private var firstName = ""
    @State private var familyName = ""
    @State private var phoneNumber = ""
    @State private var gender = "Female"
    @State private var birthDate: Date?

    // Account Info
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
                
    // Vehicle Info
    @State private var licenseNumber = ""
    @State private var licenseExpiryDate: Date?
    @State private var vehicleMake = ""
    @State private var vehicleModel = ""
    @State private var vehicleYear = ""
    @State private var vehicleColor = ""
    @State private var plateNumber = ""
    
    // Documents
    @State private var licenseFrontFileURL: URL?
    @State private var licenseBackFileURL: URL?
    @State private var nationalityIdFileURL: URL?
    @State private var residentCardFrontFileURL: URL?
    @State private var residentCardBackFileURL: URL?
    @State private var passportFileURL: URL?
    @State private var otherFileURLs: [URL] = []
    @State private var showCameraPicker = false
    @State private var cameraTarget: DocumentCaptureTarget = .licenseFront

    // General State
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            // Step Indicator
            HStack {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.5))
                        .frame(height: 6)
                }
            }
            .padding()

            TabView(selection: $currentStep) {
                PersonalInfoStep(
                    firstName: $firstName, familyName: $familyName,
                    phoneNumber: $phoneNumber, gender: $gender,
                    birthDate: $birthDate
                ).tag(0)
                
                AccountStep(
                    email: $email, password: $password,
                    confirmPassword: $confirmPassword
                ).tag(1)
                
                VehicleStep(
                    licenseNumber: $licenseNumber, licenseExpiryDate: $licenseExpiryDate,
                    vehicleMake: $vehicleMake, vehicleModel: $vehicleModel,
                    vehicleYear: $vehicleYear, vehicleColor: $vehicleColor,
                    plateNumber: $plateNumber,
                    licenseFrontFileName: licenseFrontFileURL?.lastPathComponent ?? "No file selected",
                    licenseBackFileName: licenseBackFileURL?.lastPathComponent ?? "No file selected",
                    nationalityIdFileName: nationalityIdFileURL?.lastPathComponent ?? "No file selected",
                    residentCardFrontFileName: residentCardFrontFileURL?.lastPathComponent ?? "No file selected",
                    residentCardBackFileName: residentCardBackFileURL?.lastPathComponent ?? "No file selected",
                    passportFileName: passportFileURL?.lastPathComponent ?? "No file selected (optional)",
                    otherFilesCount: otherFileURLs.count,
                    onCaptureLicenseFront: { openCamera(for: .licenseFront) },
                    onCaptureLicenseBack: { openCamera(for: .licenseBack) },
                    onCaptureNationalityId: { openCamera(for: .nationalityId) },
                    onCaptureResidentCardFront: { openCamera(for: .residentCardFront) },
                    onCaptureResidentCardBack: { openCamera(for: .residentCardBack) },
                    onCapturePassport: { openCamera(for: .passport) },
                    onCaptureOtherFiles: { openCamera(for: .other) }
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            // Buttons
            HStack {
                if authVM.state == .loading {
                    ProgressView()
                } else if currentStep < 2 {
                    Button("Continue") {
                        if validateStep() {
                            withAnimation { currentStep += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Register") {
                        if validateStep() {
                            submitRegistration()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Step \(currentStep + 1) of 3")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: prevStep) {
                    Image(systemName: "arrow.backward")
                }
            }
        }
        .onChange(of: authVM.state) { newValue in
            if case .error(let msg) = newValue {
                errorMessage = msg
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraImagePicker { image in
                handleCapturedImage(image)
            }
        }
    }
    
    private func prevStep() {
        if currentStep > 0 {
            withAnimation { currentStep -= 1 }
        } else {
            dismiss()
        }
    }
    
    private func validateStep() -> Bool {
        errorMessage = nil
        switch currentStep {
        case 0: // Personal Info
            if firstName.isEmpty || familyName.isEmpty || phoneNumber.isEmpty {
                errorMessage = "All personal info fields are required."
                return false
            }
            if birthDate == nil {
                errorMessage = "Please select your birth date."
                return false
            }
        case 1: // Account Info
            if !email.contains("@") {
                errorMessage = "Invalid email format."
                return false
            }
            if password.count < 6 {
                errorMessage = "Password must be at least 6 characters."
                return false
            }
            if password != confirmPassword {
                errorMessage = "Passwords do not match."
                return false
            }
        case 2: // Vehicle Info
            if licenseNumber.isEmpty || vehicleMake.isEmpty || vehicleModel.isEmpty || vehicleYear.isEmpty || vehicleColor.isEmpty || plateNumber.isEmpty {
                errorMessage = "All vehicle fields are required."
                return false
            }
            if licenseFrontFileURL == nil {
                errorMessage = "Please capture your license front image."
                return false
            }
            if licenseBackFileURL == nil {
                errorMessage = "Please capture your license back image."
                return false
            }
            if nationalityIdFileURL == nil {
                errorMessage = "Please capture your nationality ID image."
                return false
            }
            if residentCardFrontFileURL == nil {
                errorMessage = "Please capture your resident card front image."
                return false
            }
            if residentCardBackFileURL == nil {
                errorMessage = "Please capture your resident card back image."
                return false
            }
            if licenseExpiryDate == nil {
                errorMessage = "Please select your license expiry date."
                return false
            }
            if Int(vehicleYear) == nil {
                errorMessage = "Vehicle year must be a number."
                return false
            }
        default:
            break
        }
        return true
    }

    private func submitRegistration() {
        guard let birthDate = birthDate,
              let licenseExpiryDate = licenseExpiryDate,
              let vehicleYearInt = Int(vehicleYear),
              let licenseFrontFileURL = licenseFrontFileURL,
              let licenseBackFileURL = licenseBackFileURL,
              let nationalityIdFileURL = nationalityIdFileURL,
              let residentCardFrontFileURL = residentCardFrontFileURL,
              let residentCardBackFileURL = residentCardBackFileURL else {
            errorMessage = "Please ensure all fields are filled correctly."
            return
        }

        authVM.registerCaptain(
            firstName: firstName, familyName: familyName, phone: phoneNumber,
            email: email, gender: gender, birthDate: birthDate, password: password,
            licenseNumber: licenseNumber, licenseExpiryDate: licenseExpiryDate,
            vehicleMake: vehicleMake, vehicleModel: vehicleModel, vehicleYear: vehicleYearInt,
            vehicleColor: vehicleColor, plateNumber: plateNumber,
            licenseFrontDocumentURL: licenseFrontFileURL,
            licenseBackDocumentURL: licenseBackFileURL,
            nationalityIdDocumentURL: nationalityIdFileURL,
            residentCardFrontDocumentURL: residentCardFrontFileURL,
            residentCardBackDocumentURL: residentCardBackFileURL,
            passportDocumentURL: passportFileURL,
            otherDocumentURLs: otherFileURLs
        )
    }

    private func openCamera(for target: DocumentCaptureTarget) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "Camera is not available on this device."
            return
        }
        cameraTarget = target
        showCameraPicker = true
    }

    private func handleCapturedImage(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to process captured image."
            return
        }

        let fileName: String
        switch cameraTarget {
        case .licenseFront:
            fileName = "license_front_\(UUID().uuidString).jpg"
        case .licenseBack:
            fileName = "license_back_\(UUID().uuidString).jpg"
        case .nationalityId:
            fileName = "nationality_id_\(UUID().uuidString).jpg"
        case .residentCardFront:
            fileName = "resident_card_front_\(UUID().uuidString).jpg"
        case .residentCardBack:
            fileName = "resident_card_back_\(UUID().uuidString).jpg"
        case .passport:
            fileName = "passport_\(UUID().uuidString).jpg"
        case .other:
            fileName = "other_\(UUID().uuidString).jpg"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try imageData.write(to: tempURL, options: .atomic)
            switch cameraTarget {
            case .licenseFront:
                licenseFrontFileURL = tempURL
            case .licenseBack:
                licenseBackFileURL = tempURL
            case .nationalityId:
                nationalityIdFileURL = tempURL
            case .residentCardFront:
                residentCardFrontFileURL = tempURL
            case .residentCardBack:
                residentCardBackFileURL = tempURL
            case .passport:
                passportFileURL = tempURL
            case .other:
                otherFileURLs.append(tempURL)
            }
        } catch {
            errorMessage = "Failed to save captured image: \(error.localizedDescription)"
        }
    }
}


// MARK: - Registration Step Sub-Views
struct PersonalInfoStep: View {
    @Binding var firstName: String
    @Binding var familyName: String
    @Binding var phoneNumber: String
    @Binding var gender: String
    @Binding var birthDate: Date?

    var body: some View {
        Form {
            Section(header: Text("Personal Information")) {
                TextField("First Name", text: $firstName)
                TextField("Family Name", text: $familyName)
                TextField("Phone Number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                
                Picker("Gender", selection: $gender) {
                    Text("Female").tag("Female")
                    Text("Male").tag("Male")
                }
                
                DatePicker(
                    "Birth Date",
                    selection: Binding(
                        get: { birthDate ?? Date() },
                        set: { birthDate = $0 }
                    ),
                    in: ...Date().addingTimeInterval(-18 * 365 * 24 * 3600), // Must be 18+
                    displayedComponents: .date
                )
            }
        }
    }
}

struct AccountStep: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String

    var body: some View {
        Form {
            Section(header: Text("Account Details")) {
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                SecureField("Confirm Password", text: $confirmPassword)
            }
        }
    }
}

struct VehicleStep: View {
    @Binding var licenseNumber: String
    @Binding var licenseExpiryDate: Date?
    @Binding var vehicleMake: String
    @Binding var vehicleModel: String
    @Binding var vehicleYear: String
    @Binding var vehicleColor: String
    @Binding var plateNumber: String
    let licenseFrontFileName: String
    let licenseBackFileName: String
    let nationalityIdFileName: String
    let residentCardFrontFileName: String
    let residentCardBackFileName: String
    let passportFileName: String
    let otherFilesCount: Int
    let onCaptureLicenseFront: () -> Void
    let onCaptureLicenseBack: () -> Void
    let onCaptureNationalityId: () -> Void
    let onCaptureResidentCardFront: () -> Void
    let onCaptureResidentCardBack: () -> Void
    let onCapturePassport: () -> Void
    let onCaptureOtherFiles: () -> Void

    var body: some View {
        Form {
            Section(header: Text("Vehicle Information")) {
                TextField("License Number", text: $licenseNumber)
                DatePicker(
                    "License Expiry Date",
                    selection: Binding(
                        get: { licenseExpiryDate ?? Date() },
                        set: { licenseExpiryDate = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                
                TextField("Vehicle Make (e.g., Toyota)", text: $vehicleMake)
                TextField("Vehicle Model (e.g., Camry)", text: $vehicleModel)
                TextField("Vehicle Year (e.g., 2022)", text: $vehicleYear)
                    .keyboardType(.numberPad)
                TextField("Vehicle Color", text: $vehicleColor)
                TextField("Plate Number", text: $plateNumber)
                    .autocapitalization(.allCharacters)
            }

            Section(header: Text("Documents")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License Front")
                        Text(licenseFrontFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCaptureLicenseFront() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License Back")
                        Text(licenseBackFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCaptureLicenseBack() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nationality ID")
                        Text(nationalityIdFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCaptureNationalityId() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resident Card Front")
                        Text(residentCardFrontFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCaptureResidentCardFront() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resident Card Back")
                        Text(residentCardBackFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCaptureResidentCardBack() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passport (Optional)")
                        Text(passportFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Capture") { onCapturePassport() }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Other Files")
                        Text("\(otherFilesCount) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Capture") { onCaptureOtherFiles() }
                }
            }
        }
    }
}

private enum DocumentCaptureTarget {
    case licenseFront
    case licenseBack
    case nationalityId
    case residentCardFront
    case residentCardBack
    case passport
    case other
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct RegisterScreen_Previews: PreviewProvider {
    static var previews: some View {
        RegisterScreen()
    }
}
