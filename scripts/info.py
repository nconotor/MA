import matplotlib.pyplot as plt
import pandas as pd
import numpy as np 
import sys
import re
from io import StringIO

def plot_data_split(df):
    """Generates a plot with separate subplots for each CPU."""
    fig, axes = plt.subplots(nrows=df['CPU'].nunique(), figsize=(10, 6))

    for i, (cpu, group) in enumerate(df.groupby('CPU')):
        axes[i].plot(group['Tick'], group['Latency'], linestyle='-')
        axes[i].set_title(f'CPU {cpu} Latency over Time')
        axes[i].set_xlabel('Tick')
        axes[i].set_ylabel('Latency')

    plt.tight_layout()
    plt.savefig('timeseries_split.png')

def plot_data_combined(df):
    """Generates a single plot for all CPUs."""
    plt.figure(figsize=(10, 6))

    for cpu, group in df.groupby('CPU'):
        plt.plot(group['Tick'], group['Latency'], linestyle='-', label=f'CPU {cpu}')

    plt.title('CPU Latencies over Time')
    plt.xlabel('Tick')
    plt.ylabel('Latency')
    plt.legend()
    plt.tight_layout()
    plt.savefig('timeseries.png')

def write_high_latency_info(df, output_file):
    """Writes lines with latencies greater than 1000 to an output file."""
    # Filter the DataFrame for rows where Latency is greater than 1000
    high_latency_df = df[df['Latency'] > 1000]

    # Format the DataFrame as a string with the desired format
    formatted_lines = high_latency_df.apply(lambda row: f"{row['CPU']}: {row['Tick']}: {row['Latency']}", axis=1)

    # Write the formatted lines to the output file
    with open(output_file, 'w') as out_file:
        for line in formatted_lines:
            out_file.write(line + '\n')



def read_and_filter_data(file_path):
    """Reads and filters the file to extract CPU, Tick, and Latency."""
    filtered_data = []

    with open(file_path, 'r') as file:
        for line in file:
            if re.match(r'^\s*\d+:\s+\d+:\s+\d+\s+\d+\s*$', line):
                parts = line.split(':')
                filtered_data.append([int(parts[0].strip()), int(parts[1].strip()), int(parts[2].split()[0].strip())])

    return pd.DataFrame(filtered_data, columns=['CPU', 'Tick', 'Latency'])

def plot_histogram(file_path, step=50):
    """Generates histograms from the cyclictest output and annotates latency and overflow info."""
    with open(file_path, 'r') as file:
        content = file.read()

    # Extracting latency and overflow information
    max_latencies = list(map(int, re.findall(r'\b\d+\b', re.search(r"Max Latencies:.*", content).group(0))))
    min_latencies = list(map(int, re.findall(r'\b\d+\b', re.search(r"Min Latencies:.*", content).group(0))))
    avg_latencies = list(map(int, re.findall(r'\b\d+\b', re.search(r"Avg Latencies:.*", content).group(0))))
    total_latencies = list(map(int, re.findall(r'\b\d+\b', re.search(r"Total:.*", content).group(0))))
    overflows = list(map(int, re.findall(r'\b\d+\b', re.search(r"Histogram Overflows:.*", content).group(0))))

    # Extracting histogram data
    histogram_data = [line.split() for line in content.split('\n') if line and not line.startswith('#') and line[0].isdigit()]
    df = pd.DataFrame(histogram_data).astype(int)

    cores = df.shape[1] - 1
    fig, axes = plt.subplots(nrows=cores, figsize=(10, cores * 4))

    for i in range(1, cores + 1):
        axes[i-1].bar(df[0], df[i], width=1, log=True)
        axes[i-1].set_title(f'CPU {i-1} Latency Histogram')
        axes[i-1].set_xlabel('Latency (us)')
        axes[i-1].set_ylabel('Number of latency samples')
        axes[i-1].set_xlim(0, 400)
        axes[i-1].set_xticks(np.arange(0, 401, step))
        axes[i-1].grid(True)

        # Annotating latency and overflow information
        info_text = (f"Total: {total_latencies[i-1]}, Min: {min_latencies[i-1]}, "
                     f"Avg: {avg_latencies[i-1]}, Max: {max_latencies[i-1]}, Overflows: {overflows[i-1]}")
        axes[i-1].text(0.98, 0.95, info_text, horizontalalignment='right', verticalalignment='top',
                       transform=axes[i-1].transAxes, fontsize=8, bbox=dict(facecolor='white', alpha=0.5))

    plt.tight_layout()
    plt.savefig('histogram.png')

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python info.py <filename>")
        sys.exit(1)

    file_path = sys.argv[1]
    df = read_and_filter_data(file_path)

    # Perform all actions
    plot_data_split(df)
    plot_data_combined(df)
    write_high_latency_info(df, "high_latency_info.txt")
    plot_histogram(file_path)  # Plot histogram from cyclictest output