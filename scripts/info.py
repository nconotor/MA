import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
import sys
import re
import json
import seaborn as sns
from io import StringIO
import os

def read_and_filter_data(file_path):
    """Reads and filters the file to extract CPU, Tick, and Latency."""
    pattern = re.compile(r'^\s*(\d+):\s+(\d+):\s+(\d+)\s+\d+\s*$')
    
    with open(file_path, 'r') as file:
        filtered_data = [
            [int(match.group(1)), int(match.group(2)), int(match.group(3))]
            for line in file if (match := pattern.match(line))
    ]

    return pd.DataFrame(filtered_data, columns=['CPU', 'Tick', 'Latency'])

def plot_timeseries(df, smoothing_method='max'):
    """Generates a combined plot and individual CPU-specific plots with explicit color access."""
    
    sns.set_palette("tab10")
    custom_colors = sns.color_palette()
    plt.figure(figsize=(10, 6))

    for cpu, group in df.groupby('CPU'):
        window_size = max(len(group) // 100, 1)  
        if smoothing_method == 'max':
            latency_values = group['Latency'].rolling(window=window_size, min_periods=1).max()
        elif smoothing_method == 'mean':
            latency_values = group['Latency'].rolling(window=window_size, min_periods=1).mean()
        else:
            latency_values = group['Latency']
        
        plt.plot(group['Tick'], latency_values, linestyle='-', label=f'CPU {cpu}', alpha=0.7, color=custom_colors[cpu-1])

    plt.title(f'{smoothing_method.capitalize()} CPU Latencies over Time')
    plt.xlabel('Tick')
    plt.ylabel(f'Latency ({smoothing_method.capitalize()})')
    plt.legend()
    plt.grid(True)  
    plt.tight_layout()
    plt.savefig(f'graphics/timeseries_{smoothing_method}.png')
    plt.close()

    for cpu, group in df.groupby('CPU'):
        plt.figure(figsize=(10, 6))
        window_size = max(len(group) // 100, 1)
        if smoothing_method == 'max':
            latency_values = group['Latency'].rolling(window=window_size, min_periods=1).max()
        elif smoothing_method == 'mean':
            latency_values = group['Latency'].rolling(window=window_size, min_periods=1).mean()
        else:
            latency_values = group['Latency']

        plt.plot(group['Tick'], latency_values, linestyle='-', label=f'CPU {cpu}', alpha=0.7, color=custom_colors[cpu-1])
        plt.title(f'CPU {cpu} {smoothing_method.capitalize()} Latency over Time')
        plt.xlabel('Tick')
        plt.ylabel(f'Latency ({smoothing_method.capitalize()})')
        plt.legend()
        plt.grid(True)
        plt.tight_layout()
        plt.savefig(f'graphics/timeseries_{cpu}_{smoothing_method}.png')
        plt.close()

def plot_histogram(file_path, step=50):
    """Generates two histograms."""
    with open(file_path, 'r') as file:
        data = json.load(file)

    histograms = []
    for thread_id, thread_data in data['thread'].items():
        for latency, count in thread_data['histogram'].items():
            histograms.append({'Thread': thread_id, 'Latency': int(latency), 'Count': count})

    df = pd.DataFrame(histograms)

    sns.set_palette("tab10")
    custom_colors = sns.color_palette()

    grouped = df.groupby('Thread')

    for thread_id, group in grouped:
        fig, ax = plt.subplots(figsize=(10, 4))
        ax.bar(group['Latency'], group['Count'], width=1, log=True, color=custom_colors[int(thread_id) - 1], linewidth=1)
        ax.set_title(f'CPU {thread_id} Latency Histogram')
        ax.set_xlabel('Latency (us)')
        ax.set_ylabel('Number of latency samples')
        ax.set_xlim(0, 400)
        ax.set_xticks(np.arange(0, 401, step))
        ax.grid(True)

        min_latency = data['thread'][thread_id]['min']
        max_latency = data['thread'][thread_id]['max']
        avg_latency = data['thread'][thread_id]['avg']
        total_samples = sum(group['Count'])
        overflows = data['thread'][thread_id]['cycles'] - total_samples

        info_text = (f"Total: {total_samples}, Min: {min_latency}, "
                     f"Avg: {avg_latency}, Max: {max_latency}, Overflows: {overflows}")
        ax.text(0.98, 0.95, info_text, horizontalalignment='right', verticalalignment='top',
                transform=ax.transAxes, fontsize=8, bbox=dict(facecolor='white', alpha=0.5))

        plt.tight_layout()
        plt.savefig(f'graphics/histogram_{thread_id}.png')
        plt.close()  

    colors = plt.cm.viridis(np.linspace(0, 1, len(grouped)))

    fig, ax = plt.subplots(figsize=(10, 4))
    legend_labels = [] 

    for i, (thread_id, group) in enumerate(grouped):
        ax.bar(group['Latency'], group['Count'], width=1, log=True, color=custom_colors[i], alpha=0.7 - i * 0.15, linewidth=1)

        min_latency = data['thread'][thread_id]['min']
        max_latency = data['thread'][thread_id]['max']
        avg_latency = data['thread'][thread_id]['avg']
        total_samples = sum(group['Count'])
        overflows = data['thread'][thread_id]['cycles'] - total_samples

        label = (f'CPU {thread_id}: Total={total_samples}, Min={min_latency}, '
                f'Avg={avg_latency}, Max={max_latency}, Overflows={overflows}')
        legend_labels.append(label)

    ax.set_title('Latency Histogram')
    ax.set_xlabel('Latency (us)')
    ax.set_ylabel('Number of latency samples')
    ax.set_xlim(0, 400)
    ax.set_xticks(np.arange(0, 401, step))
    ax.grid(True)
    ax.legend(legend_labels)

    plt.tight_layout()
    plt.savefig('graphics/histogram.png')
    plt.close()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python info.py <filename>")
        sys.exit(1)
    
    file_path = sys.argv[1]
    os.makedirs('graphics', exist_ok=True)

    df = read_and_filter_data(file_path)
    plot_histogram(file_path + ".json")  

    for smoothing_method in ['max', 'mean', 'none']:
        plot_timeseries(df, smoothing_method)
