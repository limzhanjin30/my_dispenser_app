import 'package:flutter/material.dart';
import 'main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // 1. Create controllers for the fields
  final TextEditingController _newNameController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String selectedRole = 'Patient';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Logo and Header
              Column(
                children: [
                  const Icon(Icons.add_moderator, color: Colors.blue, size: 40),
                  const Text(
                    "Smart Medicine\nDispenser",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Text(
                "Create an Account",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // --- UPDATED ROLE SELECTION (Same Size Boxes) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildRoleItem("Patient", Icons.person, Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildRoleItem(
                      "Caregiver",
                      Icons.groups,
                      Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildRoleItem(
                      "Healthcare\nProvider",
                      Icons.medical_services,
                      Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Sign Up Input Fields
              _buildTextField(
                "Full Name",
                _newNameController,
              ), // You can create a _nameController if needed
              const SizedBox(height: 15),

              _buildTextField(
                "Email",
                _newEmailController,
              ), // Linked to your controller
              const SizedBox(height: 15),

              _buildTextField(
                "Phone Number",
                TextEditingController(),
              ), // You can create a _phoneController if needed
              const SizedBox(height: 15),

              _buildTextField(
                "Password",
                _newPasswordController,
                isObscure: true,
              ), // Linked to your controller
              const SizedBox(height: 15),

              _buildTextField(
                "Confirm Password",
                _confirmPasswordController,
                isObscure: true,
              ), // Linked to your controller
              const SizedBox(height: 30),

              // Sign Up Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    String name = _newNameController.text.trim();
                    String email = _newEmailController.text.trim();
                    String password = _newPasswordController.text;

                    // 1. Basic Validation
                    if (password != _confirmPasswordController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Passwords do not match!"),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (name.isEmpty || email.isEmpty || password.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please fill in all fields"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    try {
                      // 2. Create the user in Firebase Authentication
                      UserCredential userCredential = await FirebaseAuth
                          .instance
                          .createUserWithEmailAndPassword(
                            email: email,
                            password: password,
                          );

                      // 3. Save the user's custom data (Role, Name) to Firestore Database
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(userCredential.user!.uid)
                          .set({
                            'name': name,
                            'email': email,
                            'role':
                                selectedRole, // 'Patient', 'Caregiver', or 'Healthcare\nProvider'
                            'createdAt': DateTime.now(),
                          });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Account created successfully as $selectedRole",
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pop(context); // Go back to login screen
                    } on FirebaseAuthException catch (e) {
                      // 4. Handle Firebase Errors (like email already exists)
                      String errorMessage = "An error occurred during sign up.";
                      if (e.code == 'email-already-in-use') {
                        errorMessage =
                            "The email is already registered. Please log in.";
                      } else if (e.code == 'weak-password') {
                        errorMessage = "The password is too weak.";
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error: ${e.toString()}"),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Sign Up",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account? "),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      "Login",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    TextEditingController controller, {
    bool isObscure = false,
  }) {
    return TextField(
      controller: controller, // This links the UI to your data
      obscureText: isObscure,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --- UPDATED HELPER (Removed fixed width for Expanded support) ---
  Widget _buildRoleItem(String label, IconData icon, Color color) {
    bool isSelected = selectedRole == label;
    return GestureDetector(
      onTap: () => setState(() => selectedRole = label),
      child: Container(
        height: 100, // Fixed height to keep them level
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.05) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
