import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class PatientPassword extends StatefulWidget {
  final String userEmail; // Pass email to identify the user in Firestore
  const PatientPassword({super.key, required this.userEmail});

  @override
  State<PatientPassword> createState() => _PatientPasswordState();
}

class _PatientPasswordState extends State<PatientPassword> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _isLoading = false;

  Future<void> _updateDispenserPin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final String cleanEmail = widget.userEmail.trim().toLowerCase();
      
      // 1. Find the user document
      var userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        // 2. Update the 'dispenserPin' field in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userSnapshot.docs.first.id)
            .update({'dispenserPin': _pinController.text.trim()});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Dispenser PIN updated successfully!"), backgroundColor: Colors.teal),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showError("Failed to update PIN: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Dispenser Security", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Set Dispenser PIN", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
              const SizedBox(height: 10),
              const Text("This 4-digit PIN will be required every time you take your medication to unlock the hardware.", 
                style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 35),
              
              _buildPinField("New 4-Digit PIN", _pinController),
              const SizedBox(height: 20),
              _buildPinField("Confirm PIN", _confirmPinController, isConfirm: true),
              
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateDispenserPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A3B70),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Save PIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinField(String label, TextEditingController controller, {bool isConfirm = false}) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(letterSpacing: 10, fontSize: 20, fontWeight: FontWeight.bold),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF1A3B70)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Required";
        if (value.length != 4) return "Must be 4 digits";
        if (isConfirm && value != _pinController.text) return "PINs do not match";
        return null;
      },
    );
  }
}