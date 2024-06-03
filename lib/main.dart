import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';

import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:exif/exif.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Note Cam',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  late img.BitmapFont _font;

  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _customNoteController =
      TextEditingController(text: "");

  DateTime _selectedDateTime = DateTime.now();
  String elevation = "";
  String accuracy = "";

  @override
  void initState() {
    super.initState();
    _loadFont();

    getLocation();
  }

  void _loadFont() {
    _font =
        img.arial_48; // Using the largest available font in the image package
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _addWatermarkAndSave() async {
    if (_image == null) return;

    // Read the image from file
    final bytes = await _image!.readAsBytes();
    img.Image originalImage = img.decodeImage(Uint8List.fromList(bytes))!;

    // Fix the image orientation based on EXIF data
    final data = await readExifFromBytes(bytes);
    if (data.isNotEmpty && data.containsKey('Image Orientation')) {
      final orientation = data['Image Orientation']?.printable;
      originalImage = _fixExifOrientation(originalImage, orientation);
    }

    // Create a multiline watermark text
    List<String> watermarkLines = [
      'Latitude : ${_latitudeController.text}',
      'Longitude : ${_longitudeController.text}',
      'Elevation : $elevation',
      'Accuracy : $accuracy',
      'Time: ${_selectedDateTime.day}-${_selectedDateTime.month}-${_selectedDateTime.year} ${_selectedDateTime.hour}:${_selectedDateTime.minute}',
    ];

    // Calculate the size of the watermark box
    int padding = 10;
    int maxWidth = 0;
    int lineHeight = _font.lineHeight; // Using the height of the font

    if (_customNoteController.text != "") {
      watermarkLines.add('Note: ${_customNoteController.text}');
    }

    for (var line in watermarkLines) {
      int lineWidth = _approximateTextWidth(line, _font);
      if (lineWidth > maxWidth) {
        maxWidth = lineWidth;
      }
    }
    final boxWidth = maxWidth + 2 * padding; // Adding padding on both sides
    final boxHeight = (lineHeight + 5) * watermarkLines.length + 2 * padding;

    // Create a translucent box
    int boxX = padding; // Adjusted to left side
    int boxY = originalImage.height - boxHeight - padding; // Adjusted to bottom

    img.fillRect(
      originalImage,
      boxX,
      boxY,
      boxX + boxWidth,
      boxY + boxHeight,
      img.getColor(255, 255, 255, 128), // White with reduced opacity
    );

    // Draw the multiline watermark text
    int textX = boxX + padding;
    int textY = boxY + padding;
    for (var line in watermarkLines) {
      img.drawString(
        originalImage,
        _font,
        textX,
        textY,
        line,
        color: img.getColor(0, 0, 0), // Set color to black
      );
      textY += lineHeight + 5; // Move to the next line
    }

    // Get the temporary directory to save the image
    final tempDir = await getTemporaryDirectory();
    final watermarkedFile = File('${tempDir.path}/watermarked_image.png')
      ..writeAsBytesSync(img.encodePng(originalImage));

    // Save the image to the gallery
    await GallerySaver.saveImage(watermarkedFile.path);

    // Update the state with the watermarked image
    setState(() {
      _image = watermarkedFile;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image saved to gallery!')));
    }
  }

  int _approximateTextWidth(String text, img.BitmapFont font) {
    // Approximate the text width based on character count and font size
    // This is a rough estimate and may not be perfectly accurate
    int characterWidth =
        (font.base ~/ 2) + 2; // A rough estimate for character width
    return text.length * characterWidth;
  }

  img.Image _fixExifOrientation(img.Image image, String? orientation) {
    switch (orientation) {
      case 'Rotated 90 CW':
        return img.copyRotate(image, 90);
      case 'Rotated 180':
        return img.copyRotate(image, 180);
      case 'Rotated 270 CW':
        return img.copyRotate(image, -90);
      default:
        return image;
    }
  }

  Future<void> _showWatermarkSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Watermark Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Latitude:'),
              TextFormField(
                controller: _latitudeController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              const Text('Longitude:'),
              TextFormField(
                controller: _longitudeController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              const Text('Note:'),
              TextFormField(
                controller: _customNoteController,
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 10),
              const Text('Date & Time:'),
              InkWell(
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDateTime,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (pickedDate != null) {
                    setState(() {
                      _selectedDateTime = pickedDate;
                    });
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today),
                    const SizedBox(width: 10),
                    Text(
                      '${_selectedDateTime.day}/${_selectedDateTime.month}/${_selectedDateTime.year}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                // Save settings and apply watermark
                Navigator.of(context).pop();
                _addWatermarkAndSave();
              },
              child: const Text('Apply Watermark'),
            ),
          ],
        );
      },
    );
  }

  Future<void> getLocation() async {
    Location location = Location();

    bool serviceEnabled;
    PermissionStatus permissionGranted;
    LocationData locationData;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    locationData = await location.getLocation();

    setState(() {
      _latitudeController.text = locationData.latitude!.toStringAsFixed(6);
      _longitudeController.text = locationData.longitude!.toStringAsFixed(6);
      accuracy = locationData.accuracy!.toStringAsFixed(1);
      elevation = locationData.altitude!.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Picker & Watermark'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _image != null
                  ? Image.file(_image!)
                  : const Text('No image selected.'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Pick Image from Gallery'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _showWatermarkSettingsDialog,
                child: const Text('Add Watermark and Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
