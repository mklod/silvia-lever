import re
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime, timedelta
import pandas as pd
from matplotlib.widgets import RangeSlider

def parse_log_file(log_path):
    """Parse the log file and extract sensor data and commands"""
    sensor_data = []
    command_data = []
    
    with open(log_path, 'r') as file:
        for line in file:
            timestamp_match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:,(\d{3}))?', line)
            if timestamp_match:
                time_str = timestamp_match.group(1)
                timestamp = datetime.strptime(time_str, '%Y-%m-%d %H:%M:%S')
                if timestamp_match.group(2):  # milliseconds
                    timestamp = timestamp.replace(microsecond=int(timestamp_match.group(2)) * 1000)
            else:
                # fallback day + time only, e.g. "18 12:28:41"
                timestamp_match = re.search(r'(\d{2}) (\d{2}:\d{2}:\d{2})', line)
                if timestamp_match:
                    time_str = f"2025-08-{timestamp_match.group(1)} {timestamp_match.group(2)}"
                    timestamp = datetime.strptime(time_str, '%Y-%m-%d %H:%M:%S')
                else:
                    continue
                    
            if 'RECVIEVED:' in line:
                data_match = re.search(r'DATA:([0-9,\-\.]+)', line)
                if data_match:
                    parts = data_match.group(1).split(',')
                    if len(parts) >= 7:
                        try:
                            sensor_data.append({
                                'timestamp': timestamp,
                                'state': int(parts[0]),
                                'temperature': float(parts[1]),
                                'pressure': float(parts[2]),
                                'weight': float(parts[3]),
                                'pump': int(parts[4]),
                                'valve': int(parts[5]),
                                'heater': int(parts[6]),
                                'brewtime': int(parts[7]) if len(parts) > 7 else 0,
                                'tared': int(parts[8]) if len(parts) > 8 else 0
                            })
                            # print(sensor_data[len(sensor_data) - 1])
                        except ValueError:
                            continue
            
            # Extract command data
            elif 'CMD_SENT:' in line:
                cmd_text = line.split('CMD_SENT:')[1].strip()
                command_data.append({
                    'timestamp': timestamp,
                    'command': cmd_text
                })
    
    return pd.DataFrame(sensor_data), pd.DataFrame(command_data)

def visualize_data(sensor_df, command_df):
    """Create visualization of the sensor data with command events"""
    # fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(12, 10))
    fig, (ax1, ax2, ax3, ax4, ax5) = plt.subplots(5, 1, figsize=(12, 10))
       
    # System state plot
    state_names = ["IDLE", "HEATING_BREW", "HEATING_STEAM", "BREWING", "STEAMING", "FLUSHING"]
    ax4.plot(sensor_df['timestamp'], sensor_df['state'], 'm-', linewidth=2, marker='o', markersize=3)
    ax4.set_ylabel('System State', color='magenta')
    ax4.set_yticks(range(len(state_names)))
    ax4.set_yticklabels(state_names)
    ax4.grid(True, alpha=0.3)
    
    # Heater and valves status
    ax5.fill_between(sensor_df['timestamp'], 0, sensor_df['heater'], alpha=0.7, color='red', label='Heater')
    ax5.fill_between(sensor_df['timestamp'], 1, 1 + sensor_df['valve'], alpha=0.7, color='blue', label='Valve')
    ax5.fill_between(sensor_df['timestamp'], 2, 2 + sensor_df['tared'], alpha=0.7, color='cyan', label='Tared')
    ax5.set_ylabel('System Status')
    ax5.set_yticks([0.5, 1.5, 2.5])
    ax5.set_yticklabels(['Heater', 'Valve', 'Tared'])
    ax5.set_ylim(-0.5, 3.5)
    ax5.grid(True, alpha=0.3)
    ax5.legend(loc='upper right')
    
    # Temperature plot
    ax1.plot(sensor_df['timestamp'], sensor_df['temperature'], 'r-', linewidth=2)
    ax1.set_ylabel('Temperature (°C)', color='red')
    ax1.tick_params(axis='y', labelcolor='red')
    ax1.grid(True, alpha=0.3)
    ax1.set_title('Coffee Machine Sensor Data with Commands')
    
    # Pressure plot
    ax2.plot(sensor_df['timestamp'], sensor_df['pressure'], 'b-', linewidth=2)
    ax2.set_ylabel('Pressure (bar)', color='blue')
    ax2.tick_params(axis='y', labelcolor='blue')
    ax2.grid(True, alpha=0.3)
    
    # Weight plot
    ax3.plot(sensor_df['timestamp'], sensor_df['weight'], 'g-', linewidth=2)
    ax3.set_ylabel('Weight (g)', color='green')
    ax3.tick_params(axis='y', labelcolor='green')
    ax3.set_xlabel('Time')
    ax3.grid(True, alpha=0.3)
    
    # Add command events as vertical lines
    for _, cmd in command_df.iterrows():
        if 'PONG' not in cmd['command']:
            for ax in [ax1, ax2, ax3]:
                ax.axvline(x=cmd['timestamp'], color='orange', linestyle='--', alpha=0.7, linewidth=1)
    
    # Add command annotations on top plot
    y_min = sensor_df['temperature'].min()
    for i, (_, cmd) in enumerate(command_df.iterrows()):
        if 'PONG' not in cmd['command']:
            # ax1.annotate(cmd['command'][:20], 
            #             xy=(cmd['timestamp'], y_max * 0.2), 
            #             rotation=60, fontsize=7, alpha=0.8)
            print(cmd['command'])
            ax1.annotate(cmd['command'][:10], 
                        xy=(cmd['timestamp'], y_min * 1), 
                        rotation=60, fontsize=7, alpha=0.8)
    
    # Format x-axis
    # for ax in [ax1, ax2, ax3]:
    for ax in [ax1, ax2, ax3, ax4, ax5]:
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
        ax.xaxis.set_major_locator(mdates.SecondLocator(interval=30))
        plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)
    
    plt.tight_layout()
    plt.show()
    
    # Print summary
    print(f"\nSensor Data Summary:")
    print(f"Time range: {sensor_df['timestamp'].min()} to {sensor_df['timestamp'].max()}")
    print(f"Temperature: {sensor_df['temperature'].min():.1f}°C - {sensor_df['temperature'].max():.1f}°C")
    print(f"Pressure: {sensor_df['pressure'].min():.2f}bar - {sensor_df['pressure'].max():.2f}bar")
    print(f"Pump: {sensor_df['pump'].min():.2f}% - {sensor_df['pump'].max():.2f}%")
    print(f"Weight: {sensor_df['weight'].min():.1f}g - {sensor_df['weight'].max():.1f}g")
    print(f"\nCommands: {len(command_df)} events")

def visualize_data1(sensor_df, command_df):
    """Create visualization with interactive timeline slider"""
    fig = plt.figure(figsize=(14, 16))
    
    # Create subplots
    ax1 = fig.add_subplot(4, 1, 1)
    ax2 = fig.add_subplot(4, 1, 2)
    ax3 = fig.add_subplot(4, 1, 3)
    
    # Add slider subplot
    slider_ax = fig.add_subplot(4, 1, 4)
    
    axes = [ax1, ax2, ax3]
    
    # Get time range
    time_min = sensor_df['timestamp'].min()
    time_max = sensor_df['timestamp'].max()
    
    # Create range slider
    slider = RangeSlider(slider_ax, 'Time Range', 
                        mdates.date2num(time_min), 
                        mdates.date2num(time_max),
                        valinit=(mdates.date2num(time_min), mdates.date2num(time_max)))
    
    def plot_data(t_start, t_end):
        # Filter data based on time range
        mask = (sensor_df['timestamp'] >= t_start) & (sensor_df['timestamp'] <= t_end)
        filtered_df = sensor_df[mask]
        
        cmd_mask = (command_df['timestamp'] >= t_start) & (command_df['timestamp'] <= t_end)
        filtered_cmd = command_df[cmd_mask]
        
        # Clear all axes
        ax1.clear()
        ax2.clear()
        ax3.clear()
        
        if filtered_df.empty:
            return
        
        # System state plot
        # state_names = ["IDLE", "HEATING_BREW", "HEATING_STEAM", "BREWING", "STEAMING", "FLUSHING"]
        # ax4.plot(sensor_df['timestamp'], sensor_df['state'], 'm-', linewidth=2, marker='o', markersize=3)
        # ax4.set_ylabel('System State', color='magenta')
        # ax4.set_yticks(range(len(state_names)))
        # ax4.set_yticklabels(state_names)
        # ax4.grid(True, alpha=0.3)
        
        # # Heater and valves status
        # ax5.fill_between(sensor_df['timestamp'], 0, sensor_df['heater'], alpha=0.7, color='red', label='Heater')
        # ax5.fill_between(sensor_df['timestamp'], 1, 1 + sensor_df['valve'], alpha=0.7, color='blue', label='Valve')
        # ax5.fill_between(sensor_df['timestamp'], 2, 2 + sensor_df['tared'], alpha=0.7, color='cyan', label='Tared')
        # ax5.set_ylabel('System Status')
        # ax5.set_yticks([0.5, 1.5, 2.5])
        # ax5.set_yticklabels(['Heater', 'Valve', 'Tared'])
        # ax5.set_ylim(-0.5, 3.5)
        # ax5.grid(True, alpha=0.3)
        # ax5.legend(loc='upper right')
        
        # Temperature plot
        ax1.plot(filtered_df['timestamp'], filtered_df['temperature'], 'r-', linewidth=2)
        ax1.set_ylabel('Temperature (°C)', color='red')
        ax1.tick_params(axis='y', labelcolor='red')
        ax1.grid(True, alpha=0.3)
        ax1.set_title('Coffee Machine Sensor Data with Commands')
        
        # Pressure plot
        ax2.plot(filtered_df['timestamp'], filtered_df['pump'], 'b-', linewidth=2)
        ax2.set_ylabel('Pressure (bar)', color='blue')
        ax2.tick_params(axis='y', labelcolor='blue')
        ax2.grid(True, alpha=0.3)
        
        # Weight plot
        ax3.plot(filtered_df['timestamp'], filtered_df['weight'], 'g-', linewidth=2)
        ax3.set_ylabel('Weight (g)', color='green')
        ax3.tick_params(axis='y', labelcolor='green')
        ax3.set_xlabel('Time')
        ax3.grid(True, alpha=0.3)
        
        # Add command events as vertical lines
        for _, cmd in filtered_cmd.iterrows():
            for ax in [ax1, ax2, ax3]:
                ax.axvline(x=cmd['timestamp'], color='orange', linestyle='--', alpha=0.7, linewidth=1)
        
        # Add command annotations on top plot
        y_min = filtered_df['temperature'].min()
        for i, (_, cmd) in enumerate(filtered_cmd.iterrows()):
            if 'PONG' not in cmd['command']:
                print(cmd['command'])
                ax1.annotate(cmd['command'][:10], 
                            xy=(cmd['timestamp'], y_min * 1), 
                            rotation=60, fontsize=7, alpha=0.8)
        
        # Format x-axis
        for ax in [ax1, ax2, ax3]:
        # for ax in [ax1, ax2, ax3, ax4, ax5]:
            ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
            ax.xaxis.set_major_locator(mdates.SecondLocator(interval=30))
            plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)
        
        # plt.tight_layout()
        # plt.show()
        
        # Print summary
        print(f"\nSensor Data Summary:")
        print(f"Time range: {sensor_df['timestamp'].min()} to {sensor_df['timestamp'].max()}")
        print(f"Temperature: {sensor_df['temperature'].min():.1f}°C - {sensor_df['temperature'].max():.1f}°C")
        print(f"Pressure: {sensor_df['pressure'].min():.2f}bar - {sensor_df['pressure'].max():.2f}bar")
        print(f"Pump: {sensor_df['pump'].min():.2f}% - {sensor_df['pump'].max():.2f}%")
        print(f"Weight: {sensor_df['weight'].min():.1f}g - {sensor_df['weight'].max():.1f}g")
        print(f"\nCommands: {len(command_df)} events")
        
    def update_plot(val):
        t_start = mdates.num2date(slider.val[0]).replace(tzinfo=None)
        t_end = mdates.num2date(slider.val[1]).replace(tzinfo=None)
        plot_data(t_start, t_end)
    
    # Initial plot
    plot_data(time_min, time_max)
    
    # Connect slider to update function
    slider.on_changed(update_plot)
    
    plt.tight_layout()
    plt.show()
    
if __name__ == "__main__":
    log_file = r"c:\20_silvia_home_ui_only\logs\silvia_20250821_012619.log"
    
    sensor_df, command_df = parse_log_file(log_file)
    
    if not sensor_df.empty:
        print(f"Parsed {len(sensor_df)} sensor readings and {len(command_df)} commands")
        visualize_data(sensor_df, command_df)
    else:
        print("No sensor data found in log file")