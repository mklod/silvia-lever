# Configuration for Silvia Coffee Machine GUI

# Serial Communication Settings
USE_MOCK_SERIAL = False  # Set to False when connecting to real hardware
SERIAL_PORT = None  # Auto-detect if None, or specify like "COM3" on Windows
SERIAL_BAUD = 115200

# Temperature Settings
DEFAULT_BREW_TEMP = 93.0
DEFAULT_STEAM_TEMP = 130.0
MIN_BREW_TEMP = 60.0
MAX_BREW_TEMP = 110.0
MIN_STEAM_TEMP = 110.0
MAX_STEAM_TEMP = 150.0

# Safety Settings
MAX_BREW_TIME = 300  # seconds
MAX_STEAM_TIME = 600  # seconds
COMM_TIMEOUT = 10.0  # seconds

# UI Settings
WINDOW_WIDTH = 1920
WINDOW_HEIGHT = 1080
FULLSCREEN = False  # Set to True for touchscreen deployment