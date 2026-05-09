import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authManager: AuthManager // Inject AuthManager
    @StateObject private var authVM = AuthViewModel()

    @State private var firstName = ""
    @State private var familyName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var gender = "Female"
    @State private var birthDate: Date? = nil

    @State private var showDatePicker = false
    @State private var obscurePassword = true
    @State private var obscureConfirmPassword = true

    @State private var errorMessage: String?
    @State private var isRegistered = false

    let genders = ["Female", "Male"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Join LadyTaxi")
                    .font(.title)
                    .fontWeight(.bold)

                // MARK: - Name
                HStack {
                    TextField("First Name", text: $firstName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Family Name", text: $familyName)
                        .textFieldStyle(.roundedBorder)
                }

                // MARK: - Phone
                TextField("Phone Number", text: $phone)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: phone) { newValue in
                        let digitsOnly = newValue.filter(\.isNumber)
                        phone = String(digitsOnly.prefix(20))
                    }

                // MARK: - Email
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                // MARK: - Gender & Birthdate
                HStack {
                    Picker("Gender", selection: $gender) {
                        ForEach(genders, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text(birthDateText)
                        }
                    }
                }

                // MARK: - Password
                passwordField(
                    title: "Password",
                    text: $password,
                    isSecure: $obscurePassword
                )

                passwordField(
                    title: "Confirm Password",
                    text: $confirmPassword,
                    isSecure: $obscureConfirmPassword
                )

                // MARK: - Error
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                // MARK: - Register Button
                Button(action: submit) {
                    if authVM.state == .loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Register")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(authVM.state == .loading)

                Text("By registering, you agree to our Terms of Service and Privacy Policy")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDatePicker) {
            DatePicker(
                "Birth Date",
                selection: Binding(
                    get: { birthDate ?? Date() },
                    set: { birthDate = $0 }
                ),
                in: ...Date().addingTimeInterval(-16 * 365 * 24 * 3600),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
        }
        .onChange(of: authVM.state) { state in
            switch state {
            case .authenticated:
                isRegistered = true
            case .error(let msg):
                errorMessage = msg
            default:
                break
            }
        }
    }

    // MARK: - Helpers

    var birthDateText: String {
        guard let birthDate else { return "Select Birth Date" }
        return birthDate.formatted(date: .abbreviated, time: .omitted)
    }

    func submit() {
        errorMessage = nil

        guard !firstName.isEmpty,
              !familyName.isEmpty,
              phone.count >= 10,
              phone.count <= 20,
              email.contains("@"),
              password.count >= 6,
              password == confirmPassword,
              let birthDate
        else {
            errorMessage = "Please check your inputs"
            return
        }

        authVM.register(
            firstName: firstName,
            familyName: familyName,
            phone: phone,
            email: email,
            gender: gender,
            birthDate: birthDate,
            password: password,
            authManager: authManager
        )
    }

    @ViewBuilder
    func passwordField(
        title: String,
        text: Binding<String>,
        isSecure: Binding<Bool>
    ) -> some View {
        HStack {
            Group {
                if isSecure.wrappedValue {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                isSecure.wrappedValue.toggle()
            } label: {
                Image(systemName: isSecure.wrappedValue ? "eye.slash" : "eye")
            }
        }
    }
}
