import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:indriver_clone/providers/auth.dart';
import 'package:indriver_clone/ui/button.dart';
import 'package:provider/provider.dart';

class UploadDocs extends StatefulWidget {
  const UploadDocs({Key? key}) : super(key: key);

  @override
  _UploadDocsState createState() => _UploadDocsState();
}

class _UploadDocsState extends State<UploadDocs> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _driverNameController;
  late final TextEditingController _driverNumberController;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<Authentication>(context, listen: false).loggedUser;
    _driverNameController = TextEditingController(text: user.driverName ?? '');
    _driverNumberController = TextEditingController(text: user.driverNumber ?? '');
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _driverNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Driver name',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _driverNameController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter driver name';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter driver name',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Driver number',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _driverNumberController,
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter driver number';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter driver number',
                    ),
                  ),
                  const SizedBox(height: 24),
                  BotButton(
                    title: 'Submit',
                    onTap: () async {
                      if (!_formKey.currentState!.validate()) return;

                      var provider =
                          Provider.of<Authentication>(context, listen: false);
                      await provider.updateDriverProfile(
                        _driverNameController.text.trim(),
                        _driverNumberController.text.trim(),
                        context,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}