import re

log_file = r"c:\20_silvia_home_ui_only\logs\silvia_20250818_001140.log"

with open(log_file, 'r') as file:
    lines = file.readlines()
    
print("First 10 lines:")
for i, line in enumerate(lines[:10]):
    print(f"{i+1}: {line.strip()}")

print("\nLines containing 'SENSORS:':")
for i, line in enumerate(lines):
    if 'SENSORS:' in line:
        print(f"Line {i+1}: {line.strip()}")
        break