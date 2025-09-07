import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motoboy Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MotoboyTrackerScreen(),
    );
  }
}

class MotoboyTrackerScreen extends StatefulWidget {
  @override
  _MotoboyTrackerScreenState createState() => _MotoboyTrackerScreenState();
}

class _MotoboyTrackerScreenState extends State<MotoboyTrackerScreen> {
  final TextEditingController _motoboyIdController = TextEditingController();
  final TextEditingController _odometerController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();
  
  String _motoboyId = '';
  String _serverUrl = 'https://mototracker-production.up.railway.app/api';
  bool _isTracking = false;
  bool _isLoading = false;
  String _status = 'Pronto para iniciar';
  Position? _currentPosition;
  Timer? _locationTimer;
  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _motoboyId = prefs.getString('motoboy_id') ?? '';
      _serverUrl = prefs.getString('server_url') ?? 'https://mototracker-production.up.railway.app/api';
      _motoboyIdController.text = _motoboyId;
      _serverUrlController.text = _serverUrl;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('motoboy_id', _motoboyId);
    await prefs.setString('server_url', _serverUrl);
  }

  Future<void> _showSettingsDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Configurações'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _motoboyIdController,
                  decoration: InputDecoration(
                    labelText: 'ID do Motoboy',
                    hintText: 'Ex: MOT001',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _serverUrlController,
                  decoration: InputDecoration(
                    labelText: 'URL do Servidor',
                    hintText: 'https://mototracker-production.up.railway.app/api',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 Dica:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Sua URL do Railway:\nhttps://mototracker-production.up.railway.app/api',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _motoboyId = _motoboyIdController.text;
                  _serverUrl = _serverUrlController.text;
                });
                _saveSettings();
                Navigator.of(context).pop();
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final backgroundStatus = await Permission.locationAlways.request();
      return backgroundStatus.isGranted;
    }
    return false;
  }

  Future<void> _startTracking() async {
    if (_motoboyId.isEmpty) {
      _showError('Configure o ID do motoboy primeiro');
      return;
    }

    if (_odometerController.text.isEmpty) {
      _showError('Digite o valor do odômetro');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Solicitando permissões...';
    });

    // Solicitar permissões de localização
    final hasPermission = await _requestLocationPermission();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _status = 'Permissão de localização negada';
      });
      _showError('Permissão de localização é necessária para o rastreamento');
      return;
    }

    setState(() {
      _status = 'Iniciando sessão...';
    });

    try {
      // Registrar motoboy se não existir
      await _registerMotoboy();

      // Iniciar sessão
      final sessionId = await _startSession();
      if (sessionId == null) {
        throw Exception('Falha ao iniciar sessão');
      }

      _currentSessionId = sessionId;

      setState(() {
        _isTracking = true;
        _isLoading = false;
        _status = 'Rastreamento ativo';
      });

      // Iniciar envio de localização
      _startLocationUpdates();

    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Erro: ${e.toString()}';
      });
      _showError('Erro ao iniciar rastreamento: $e');
    }
  }

  Future<void> _stopTracking() async {
    if (_currentSessionId != null) {
      try {
        await _endSession(_currentSessionId!);
      } catch (e) {
        print('Erro ao finalizar sessão: $e');
      }
    }

    _locationTimer?.cancel();
    
    setState(() {
      _isTracking = false;
      _status = 'Rastreamento parado';
      _currentSessionId = null;
    });
  }

  Future<void> _registerMotoboy() async {
    final response = await http.post(
      Uri.parse('$_serverUrl/motoboys'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': _motoboyId,
        'name': 'Motoboy $_motoboyId',
        'phone': '',
      }),
    );

    if (response.statusCode != 200) {
      print('Erro ao registrar motoboy: ${response.body}');
    }
  }

  Future<String?> _startSession() async {
    final response = await http.post(
      Uri.parse('$_serverUrl/sessions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'motoboyId': _motoboyId,
        'odometer': double.parse(_odometerController.text),
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['sessionId'].toString();
    } else {
      throw Exception('Falha ao iniciar sessão: ${response.body}');
    }
  }

  Future<void> _endSession(String sessionId) async {
    final response = await http.put(
      Uri.parse('$_serverUrl/sessions/$sessionId/end'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'odometer': _odometerController.text,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao finalizar sessão: ${response.body}');
    }
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _getCurrentLocation();
    });
    
    // Primeira localização imediatamente
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
      });

      await _sendLocation(position);
    } catch (e) {
      print('Erro ao obter localização: $e');
    }
  }

  Future<void> _sendLocation(Position position) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/locations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'motoboyId': _motoboyId,
          'sessionId': _currentSessionId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        print('Localização enviada com sucesso');
      } else {
        print('Erro ao enviar localização: ${response.body}');
      }
    } catch (e) {
      print('Erro ao enviar localização: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Motoboy Tracker'),
        backgroundColor: Colors.blue[600],
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card de Status
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 16,
                        color: _isTracking ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (_currentPosition != null) ...[
                      SizedBox(height: 8),
                      Text(
                        'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Card de Configuração
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuração',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Text('ID do Motoboy: $_motoboyId'),
                    Text('Servidor: $_serverUrl'),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _showSettingsDialog,
                      icon: Icon(Icons.settings),
                      label: Text('Configurar'),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Card de Controle
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Controle de Rastreamento',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _odometerController,
                      decoration: InputDecoration(
                        labelText: 'Odômetro Inicial (km)',
                        hintText: 'Ex: 12345.6',
                        border: OutlineInputBorder(),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _startTracking,
                            icon: Icon(Icons.play_arrow),
                            label: Text('Iniciar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isTracking ? _stopTracking : null,
                            icon: Icon(Icons.stop),
                            label: Text('Parar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Spacer(),

            // Informações do Servidor
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informações do Servidor',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Dashboard: ${_serverUrl.replaceAll('/api', '')}'),
                    Text('API: $_serverUrl'),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✅ 100% GRATUITO - Railway',
                        style: TextStyle(
                          color: Colors.green[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
