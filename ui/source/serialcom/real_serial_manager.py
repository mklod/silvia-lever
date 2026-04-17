from PyQt6.QtCore import QObject, pyqtSignal, QThread
import serial
import serial.tools.list_ports
import time

class SerialReaderThread(QThread):
    line_received = pyqtSignal(str)
    
    def __init__(self, serial_port):
        super().__init__()
        self.serial_port = serial_port
        self.running = False
        
    def run(self):
        self.running = True
        while self.running and self.serial_port.is_open:
            try:
                if self.serial_port.in_waiting > 0:
                    line = self.serial_port.readline().decode('utf-8').strip()
                    if line:
                        self.line_received.emit(line)
                else:
                    time.sleep(0.01)  # Small delay to prevent busy waiting
            except Exception as e:
                print(f"Serial read error: {e}")
                break
                
    def stop(self):
        self.running = False
        self.wait()

class SerialManager(QObject):
    line_received = pyqtSignal(str)
    
    def __init__(self, port=None, baud_rate=115200):
        super().__init__()
        self.port = port
        self.baud_rate = baud_rate
        self.serial_port = None
        self.reader_thread = None
        
    def find_teensy_port(self):
        """Auto-detect Teensy port"""
        ports = serial.tools.list_ports.comports()
        for port in ports:
            # Look for Teensy in description or manufacturer
            if 'teensy' in port.description.lower() or 'teensy' in str(port.manufacturer).lower():
                return port.device
            # Also check for common Arduino/Teensy VID:PID
            if port.vid == 0x16C0:  # Teensy VID
                return port.device
        return None
        
    def start(self, port=None):
        if port:
            self.port = port
        elif not self.port:
            self.port = self.find_teensy_port()
            
        if not self.port:
            raise Exception("No Teensy port found. Please specify port manually.")
            
        try:
            self.serial_port = serial.Serial(
                port=self.port,
                baudrate=self.baud_rate,
                timeout=1,
                write_timeout=1
            )
            
            # Wait for Arduino to reset
            time.sleep(2)
            
            # Start reader thread
            self.reader_thread = SerialReaderThread(self.serial_port)
            self.reader_thread.line_received.connect(self.line_received.emit)
            self.reader_thread.start()
            
            print(f"Connected to Teensy on {self.port}")
            
        except Exception as e:
            raise Exception(f"Failed to connect to {self.port}: {e}")
            
    def stop(self):
        if self.reader_thread:
            self.reader_thread.stop()
            self.reader_thread = None
            
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            
    def send_command(self, command):
        if self.serial_port and self.serial_port.is_open:
            try:
                self.serial_port.write((command + '\n').encode('utf-8'))
                self.serial_port.flush()
            except Exception as e:
                print(f"Serial write error: {e}")
                
    def list_available_ports(self):
        """List all available serial ports"""
        ports = serial.tools.list_ports.comports()
        return [(port.device, port.description) for port in ports]