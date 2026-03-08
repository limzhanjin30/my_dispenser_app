import 'package:flutter/material.dart';
import 'Sign_up.dart';
import 'patient/patient_dashboard.dart';
import 'caregiver/caregiver_dashboard.dart';
import 'healthcare/healthcare_dashboard.dart';
import 'main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  runApp(const SmartDispenserApp());
}

class SmartDispenserApp extends StatelessWidget {
  const SmartDispenserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: LoginPage());
  }
}

bool _isObscure = true; // This tracks if password is hidden or shown

class LoginPage extends StatefulWidget {
  const LoginPage({super.key}); // Add this line

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Logic to track which role is tapped
  String selectedRole = "Patient";
  bool _isObscure = true;

  // 1. Controllers to capture text field input
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 2. Demo credentials (you can update these during your sign-up flow)
  String? registeredEmail;
  String? registeredPassword;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25.0),
          child: Column(
            children: [
              const SizedBox(height: 70),

              // --- LOGO & TITLE ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_moderator, size: 45, color: Colors.blue),
                  const SizedBox(width: 10),
                  const Text(
                    "Smart Medicine\nDispenser",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // --- ROLE SELECTION BOX ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      "Select Your Role",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        roleCard("Patient", Icons.person_outline, Colors.blue),
                        roleCard(
                          "Caregiver",
                          Icons.people_outline,
                          Colors.teal,
                        ),
                        roleCard(
                          "Healthcare\nProvider",
                          Icons.medical_services_outlined,
                          Colors.purple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // --- INPUT FIELDS ---
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // --- PASSWORD FIELD WITH VIEW FUNCTION ---
              TextField(
                obscureText: _isObscure,
                controller: _passwordController,
                decoration: InputDecoration(
                  hintText: "Password",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isObscure = !_isObscure; // Toggles the eye icon
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- UPDATED LOGIN BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () async {
                    String emailInput = _emailController.text.trim();
                    String passwordInput = _passwordController.text;

                    if (emailInput.isEmpty || passwordInput.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please enter email and password"),
                        ),
                      );
                      return;
                    }

                    try {
                      // 1. Authenticate with Firebase Auth
                      UserCredential userCredential = await FirebaseAuth
                          .instance
                          .signInWithEmailAndPassword(
                            email: emailInput,
                            password: passwordInput,
                          );

                      // 2. Fetch the user's role from Firestore Database
                      DocumentSnapshot userDoc = await FirebaseFirestore
                          .instance
                          .collection('users')
                          .doc(userCredential.user!.uid)
                          .get();

                      if (userDoc.exists) {
                        String dbRole = userDoc.get('role');

                        // 3. Verify the role matches what they selected on the screen
                        if (dbRole == selectedRole) {
                          // Navigate based on role
                          if (selectedRole == "Patient") {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    PatientDashboard(userEmail: emailInput),
                              ),
                            );
                          } else if (selectedRole == "Caregiver") {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    CaregiverDashboard(userEmail: emailInput),
                              ),
                            );
                          } else if (selectedRole == "Healthcare\nProvider") {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    HealthcareDashboard(userEmail: emailInput),
                              ),
                            );
                          }
                        } else {
                          // Deny access and sign them back out if they pick the wrong role
                          await FirebaseAuth.instance.signOut();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Access Denied: Account is registered as $dbRole.",
                              ),
                            ),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("User data not found in database."),
                          ),
                        );
                      }
                    } on FirebaseAuthException catch (e) {
                      // Handle incorrect password or email
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Invalid email or password"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Login",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- UPDATED CENTERED FOOTER (Removed Biometrics) ---
              Column(
                children: [
                  TextButton(
                    onPressed: () {
                      // Optional: Add Forgot Password logic here later
                    },
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignUpPage(),
                            ),
                          );
                        },
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGET FOR ROLE CARDS ---
  Widget roleCard(String title, IconData icon, Color themeColor) {
    bool isSelected = selectedRole == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRole = title;
        });
      },
      child: Container(
        width: 85,
        height: 100,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? themeColor : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(15),
          color: isSelected ? themeColor.withOpacity(0.05) : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: themeColor, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
