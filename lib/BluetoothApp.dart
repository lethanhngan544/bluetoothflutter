// Rename this file to bluetooth_app.dart if needed

import 'dart:convert';
import 'dart:typed_data';
import 'dart:async'; // Import async for Timer

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';

// Keep the main entry point if you want to test this screen directly during dev
// void main() => runApp(const MaterialApp(home: BluetoothApp()));

class BluetoothApp extends StatefulWidget {
  const BluetoothApp({super.key});
  @override
  State<BluetoothApp> createState() => _BluetoothAppState();
}

// Enum for clearer connection status management
enum ConnectionStatus { disconnected, connecting, connected, error }

class _BluetoothAppState extends State<BluetoothApp> {
  // Bluetooth State & Connection
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? _connection;
  BluetoothDevice? _connectedDevice; // Keep track of the connected device
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  StreamSubscription<BluetoothDiscoveryResult>? _discoveryStreamSubscription;
  StreamSubscription<Uint8List>? _dataSubscription; // For data listener
  bool _isDiscovering = false;

  List<BluetoothDevice> _devices = [];
  final ScrollController _deviceListScrollController = ScrollController();

  // Data & Charting
  final TextEditingController _textController = TextEditingController();
  String _buffer = '';
  final List<FlSpot> _points = []; // Make final
  double _x = 0;
  final int _maxPoints =
      500; // Reduced max points for better performance potentially

  // Permissions
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    // Listen to Bluetooth state changes
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      if (mounted) {
        setState(() {
          _bluetoothState = state;
          // If bluetooth is turned off while connected, update status
          if (_bluetoothState == BluetoothState.STATE_OFF &&
              _connectionStatus == ConnectionStatus.connected) {
            _disconnect(
                showSnackbar: false); // Silently disconnect internal state
          }
        });
      }
    });

    await _checkPermissions(); // Check permissions first
    if (_permissionsGranted) {
      // Get initial state
      _bluetoothState = await FlutterBluetoothSerial.instance.state;
      if (mounted) {
        setState(() {}); // Update UI with initial state
      }
      _getPairedDevices(); // Get paired devices
    }
  }

  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Location is required on Android for scanning nearby devices
      // even if you only list paired ones sometimes.
      Permission.locationWhenInUse,
    ].request();

    if (mounted) {
      setState(() {
        _permissionsGranted = statuses[Permission.bluetoothScan]!.isGranted &&
            statuses[Permission.bluetoothConnect]!.isGranted &&
            statuses[Permission.locationWhenInUse]!.isGranted;
      });
      if (!_permissionsGranted) {
        _showSnackBar("Permissions required to use Bluetooth features.");
      }
    }
  }

  Future<void> _getPairedDevices() async {
    if (!_permissionsGranted) {
      _showSnackBar("Cannot get devices: Permissions not granted.");
      return;
    }
    setState(() {
      _isDiscovering = true; // Show loading indicator conceptually
      _devices = []; // Clear previous list
    });
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    } catch (e) {
      _showSnackBar("Error getting paired devices: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
        });
      }
    }
  }

  // --- Connection Logic ---
  void _connectToDevice(BluetoothDevice device) async {
    if (_connectionStatus == ConnectionStatus.connecting)
      return; // Prevent multiple attempts

    setState(() {
      _connectionStatus = ConnectionStatus.connecting;
      _connectedDevice = device; // Store potentially connecting device
    });
    _showSnackBar("Connecting to ${device.name ?? device.address}...",
        duration: const Duration(seconds: 5));

    try {
      final conn = await BluetoothConnection.toAddress(device.address);
      if (mounted) {
        setState(() {
          _connection = conn;
          _connectionStatus = ConnectionStatus.connected;
          _points.clear(); // Clear old data on new connection
          _x = 0;
          _buffer = '';
        });
        _showSnackBar("Connected to ${device.name ?? device.address}!");

        // Start listening to incoming data
        _dataSubscription =
            _connection!.input!.listen(_onDataReceived, onDone: () {
          // Called when the connection is closed by the remote device
          if (_connectionStatus == ConnectionStatus.connected) {
            // Avoid disconnect message if manually disconnected
            _disconnect(remoteDisconnect: true);
          }
        }, onError: (error) {
          _showSnackBar("Device connection error: $error");
          _disconnect(showError: true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionStatus = ConnectionStatus.error;
          _connectedDevice = null; // Clear device on error
        });
        _showSnackBar("Connection failed: ${e.toString()}", isError: true);
        // Optional: Automatically go back to disconnected state after showing error
        // Future.delayed(Duration(seconds: 3), () {
        //   if (mounted && _connectionStatus == ConnectionStatus.error) {
        //     setState(() => _connectionStatus = ConnectionStatus.disconnected);
        //   }
        // });
      }
    }
  }

  // --- Data Reception ---
  void _onDataReceived(Uint8List data) {
    // Allocate buffer for parsed data
    List<FlSpot> newPoints = [];
    // Decode and process buffer
    _buffer += String.fromCharCodes(data);

    // Process complete lines (ending with '\n')
    int newlineIndex;
    while ((newlineIndex = _buffer.indexOf('\n')) != -1) {
      final line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1); // Keep the rest

      if (line.isNotEmpty) {
        final tokens = line.split(' '); // Split by space
        for (var token in tokens) {
          final value = double.tryParse(token);
          if (value != null) {
            // Add point using local list to batch setState calls
            newPoints.add(FlSpot(_x++, value));
          }
        }
      }
    }

    // Update state only if new points were added
    if (newPoints.isNotEmpty && mounted) {
      setState(() {
        _points.addAll(newPoints);
        // Efficiently remove old points if exceeding max
        if (_points.length > _maxPoints) {
          _points.removeRange(0, _points.length - _maxPoints);
        }
      });
    }
  }

  // --- Data Sending ---
  void _sendText(String text) async {
    if (text.isNotEmpty &&
        _connection != null &&
        _connectionStatus == ConnectionStatus.connected) {
      try {
        _connection!.output.add(Uint8List.fromList(
            utf8.encode("$text\n"))); // Add newline convention
        await _connection!.output.allSent; // Wait for data to be sent
        // Keep text in controller for potential resend? Or clear:
        // _textController.clear();
      } catch (e) {
        if (mounted)
          _showSnackBar("Error sending data: ${e.toString()}", isError: true);
        // Consider attempting disconnect/reconnect on send error
        _disconnect(showError: true);
      }
    }
  }

  // --- Disconnection Logic ---
  void _disconnect(
      {bool remoteDisconnect = false,
      bool showError = false,
      bool showSnackbar = true}) {
    _dataSubscription?.cancel(); // Cancel listener
    _connection?.dispose(); // Dispose connection

    if (mounted) {
      setState(() {
        _connection = null;
        _dataSubscription = null;
        // Only reset device if not an error state (allow retry)
        if (!showError) _connectedDevice = null;
        _connectionStatus =
            showError ? ConnectionStatus.error : ConnectionStatus.disconnected;
      });
      if (showSnackbar) {
        if (remoteDisconnect) {
          _showSnackBar("Device disconnected.", isError: true);
        } else if (!showError) {
          _showSnackBar("Disconnected.");
        }
      }
    }
  }

  @override
  void dispose() {
    _discoveryStreamSubscription?.cancel();
    _dataSubscription?.cancel();
    _connection?.dispose();
    _textController.dispose();
    _deviceListScrollController.dispose();
    super.dispose();
  }

  // --- UI Helper Widgets ---

  // SnackBar Helper
  void _showSnackBar(String message,
      {bool isError = false, Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return; // Don't show if widget is disposed
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.grey[700],
        duration: duration,
      ),
    );
  }

  // Control Button Helper
  Widget _controlButton(String label, String charToSend) {
    bool canSend = _connectionStatus == ConnectionStatus.connected;
    return ElevatedButton(
      onPressed: canSend
          ? () => _sendText(charToSend)
          : null, // Disable if not connected
      style: ElevatedButton.styleFrom(
        backgroundColor:
            canSend ? Colors.blueAccent : Colors.grey, // Visual feedback
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  // Build AppBar with dynamic actions
  AppBar _buildAppBar() {
    return AppBar(
      title: Text(_connectedDevice?.name ?? 'Bluetooth Classic'),
      actions: <Widget>[
        if (_connectionStatus == ConnectionStatus.connected)
          IconButton(
            icon: const Icon(Icons.cancel_outlined),
            tooltip: "Disconnect",
            onPressed: () => _disconnect(),
          )
        else if (_connectionStatus == ConnectionStatus.connecting)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
          )
        else // Disconnected or Error
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Paired Devices",
            onPressed: _permissionsGranted
                ? _getPairedDevices
                : null, // Only allow refresh if permissions granted
          )
      ],
    );
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        // Allow pull-to-refresh for device list
        onRefresh: _getPairedDevices,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: !_permissionsGranted
              ? _buildPermissionsWarning() // Show permissions warning
              : _buildMainContent(), // Show main content (device list or connected view)
        ),
      ),
    );
  }

  // --- Build Methods for Content Sections ---

  Widget _buildPermissionsWarning() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 60, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            "Bluetooth and Location permissions are required.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed:
                _checkPermissions, // Allow user to retry permission request
            child: const Text("Check Permissions"),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return _buildConnectedView();
      case ConnectionStatus.connecting:
        return _buildConnectingView();
      case ConnectionStatus.error:
      case ConnectionStatus.disconnected:
      default: // Fallback to disconnected view
        return _buildDeviceListView();
    }
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
              "Connecting to ${_connectedDevice?.name ?? _connectedDevice?.address ?? 'device'}..."),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _disconnect, // Allow cancelling connection attempt
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Cancel"),
          )
        ],
      ),
    );
  }

  Widget _buildDeviceListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _connectionStatus == ConnectionStatus.error
                ? "Connection failed. Select a device:"
                : "Select a Paired Device:",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _connectionStatus == ConnectionStatus.error
                    ? Colors.redAccent
                    : null)),
        const SizedBox(height: 10),
        if (_isDiscovering)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator()))
        else if (_devices.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                  _bluetoothState == BluetoothState.STATE_OFF
                      ? "Bluetooth is OFF. Please turn it on."
                      : "No paired devices found.\nPair a device in system settings first.",
                  textAlign: TextAlign.center),
            ),
          )
        else
          Expanded(
            // Make list scrollable
            child: ListView.builder(
                controller: _deviceListScrollController,
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  BluetoothDevice device = _devices[index];
                  return Card(
                    // Use cards for better visual separation
                    elevation: 2.0,
                    margin: const EdgeInsets.symmetric(
                        vertical: 4.0, horizontal: 0),
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth_drive,
                          color: Colors.blueAccent),
                      title: Text(device.name ?? "Unknown Device"),
                      subtitle: Text(device.address),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _connectToDevice(device),
                    ),
                  );
                }),
          ),
      ],
    );
  }

  Widget _buildConnectedView() {
    // Use LayoutBuilder to make chart height responsive
    return LayoutBuilder(builder: (context, constraints) {
      // Calculate height for chart (e.g., 40% of available height)
      double chartHeight = constraints.maxHeight * 0.4;
      if (chartHeight < 150) chartHeight = 150; // Minimum height

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Text (could be removed if AppBar title is sufficient)
          // Text("Connected to: ${_connectedDevice?.name ?? _connectedDevice?.address}", style: TextStyle(fontWeight: FontWeight.bold)),
          // SizedBox(height: 10),

          // Chart Area
          SizedBox(
            height: chartHeight, // Constrained height
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: _points
                        .toList(), // Ensure it's a modifiable list if needed? No, FlSpot is immutable. Copy is fine.
                    isCurved:
                        false, // Keep straight lines for performance/clarity
                    color: Colors.greenAccent,
                    dotData:
                        FlDotData(show: false), // Keep dots off for performance
                    barWidth: 1.5, // Slightly thicker line
                    isStrokeCapRound: true,
                    belowBarData: BarAreaData(
                      // Add gradient below line
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          Colors.greenAccent.withOpacity(0.3),
                          Colors.greenAccent.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  )
                ],
                titlesData: FlTitlesData(
                  // Basic Axes Titles
                  show: true,
                  rightTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false)), // Hide right titles
                  topTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: false)), // Hide top titles
                  bottomTitles: AxisTitles(
                    // Show basic bottom titles (maybe time/index based)
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: _points.length > 10
                          ? (_points.length / 5).roundToDouble()
                          : 1, // Dynamic interval
                      // getTitlesWidget: bottomTitleWidgets, // Optional custom labels
                    ),
                  ),
                  leftTitles: AxisTitles(
                    // Show basic left titles (value based)
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40, // Space for labels
                      // getTitlesWidget: leftTitleWidgets, // Optional custom labels
                    ),
                  ),
                ),
                gridData: FlGridData(
                  // Add subtle grid lines
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 1.0, // Adjust based on your data range
                  verticalInterval: _points.length > 10
                      ? (_points.length / 5).roundToDouble()
                      : 10, // Adjust based on your data rate
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withOpacity(0.1),
                      strokeWidth: 0.5,
                    );
                  },
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: Colors.white.withOpacity(0.1),
                      strokeWidth: 0.5,
                    );
                  },
                ),
                borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                // Optional: Define min/max X/Y based on data or fixed
                // minX: _points.isNotEmpty ? _points.first.x : 0,
                // maxX: _points.isNotEmpty ? _points.last.x : 100,
                // minY: -10, // Example fixed Y range
                // maxY: 10,  // Example fixed Y range
              ),
              // swapAnimationDuration: Duration(milliseconds: 150), // Optional animation
              // swapAnimationCurve: Curves.linear,
            ),
          ),
          const SizedBox(height: 15),

          // --- Controls Section ---
          // Text Field for sending custom messages
          TextField(
            controller: _textController,
            decoration: InputDecoration(
                labelText: 'Send Message',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _connectionStatus == ConnectionStatus.connected
                      ? () => _sendText(_textController.text)
                      : null,
                )),
            onSubmitted: _connectionStatus == ConnectionStatus.connected
                ? (value) =>
                    _sendText(value) // Allow sending via keyboard action
                : null,
          ),
          const SizedBox(height: 15),

          // Wrap for control buttons
          Expanded(
            // Allow controls to scroll if screen is small
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8, // Add vertical spacing between rows of buttons
                alignment: WrapAlignment.center, // Center buttons horizontally
                children: [
                  // Waveform mode buttons
                  _controlButton("Sine", '0'),
                  _controlButton("Square", '1'),
                  _controlButton("Triangle", '2'),
                  _controlButton("Sawtooth", '3'),
                  // Frequency controls
                  _controlButton("Freq -5", '4'),
                  _controlButton("Freq +5", '6'),
                  _controlButton("Freq -1", '7'),
                  _controlButton("Freq +1", '9'),
                  // Amplitude controls
                  _controlButton("Amp -", '5'),
                  _controlButton("Amp +", '8'),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
