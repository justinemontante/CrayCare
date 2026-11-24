import matplotlib.pyplot as plt

# Data
weeks = ['Week 0\n(Oct 9)', 'Week 1\n(Oct 16)', 'Week 2\n(Oct 23)', 'Week 3\n(Oct 30)', 'Week 4\n(Nov 6)', 'Week 5\n(Nov 13)']
tank_a_survivors = [100, 98, 96, 95, 95, 93]
tank_b_survivors = [100, 96, 89, 83, 78, 71]

tank_a_mortality = [0, 2, 4, 5, 5, 7]
tank_b_mortality = [0, 4, 11, 17, 22, 29]

plt.rcParams['font.sans-serif'] = 'Arial'
plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['figure.dpi'] = 300

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.5, 4.6), sharex=True)

# Plot 1: Surviving Population
ax1.plot(weeks, tank_a_survivors, marker='o', color='#1f77b4', linewidth=2.5, markersize=7, label='Tank A (CrayCare-assisted)')
ax1.plot(weeks, tank_b_survivors, marker='s', color='#d62728', linewidth=2.5, markersize=7, linestyle='--', label='Tank B (Manual management)')

ax1.set_title('A. Weekly Surviving Population', fontsize=12, fontweight='bold', pad=12)
ax1.set_ylabel('Number of Surviving Crayfish', fontsize=11, fontweight='bold')
ax1.set_ylim(65, 105)
ax1.grid(True, linestyle=':', alpha=0.6)
ax1.legend(loc='lower left', frameon=True, fontsize=9.5)

# Annotations on Plot 1
for i, txt in enumerate(tank_a_survivors):
    y_offset = 7
    if i == 4:  # Week 4 Tank A
        y_offset = 8
    ax1.annotate(str(txt), (weeks[i], tank_a_survivors[i]), textcoords="offset points", xytext=(0, y_offset), ha='center', fontsize=9, fontweight='bold', color='#1f77b4')

for i, txt in enumerate(tank_b_survivors):
    ax1.annotate(str(txt), (weeks[i], tank_b_survivors[i]), textcoords="offset points", xytext=(0, -14), ha='center', fontsize=9, fontweight='bold', color='#d62728')

# Plot 2: Cumulative Mortality Rate
ax2.plot(weeks, tank_a_mortality, marker='o', color='#1f77b4', linewidth=2.5, markersize=7, label='Tank A (CrayCare-assisted)')
ax2.plot(weeks, tank_b_mortality, marker='s', color='#d62728', linewidth=2.5, markersize=7, linestyle='--', label='Tank B (Manual management)')

ax2.set_title('B. Cumulative Mortality Rate (%)', fontsize=12, fontweight='bold', pad=12)
ax2.set_ylabel('Cumulative Mortality (%)', fontsize=11, fontweight='bold')
ax2.set_ylim(-2, 35)
ax2.grid(True, linestyle=':', alpha=0.6)
ax2.legend(loc='upper left', frameon=True, fontsize=9.5)

# Annotations on Plot 2
for i, txt in enumerate(tank_a_mortality):
    y_off = 7
    if i == 4:
        y_off = 8
    ax2.annotate(f"{txt}%", (weeks[i], tank_a_mortality[i]), textcoords="offset points", xytext=(0, y_off), ha='center', fontsize=9, fontweight='bold', color='#1f77b4')

for i, txt in enumerate(tank_b_mortality):
    ax2.annotate(f"{txt}%", (weeks[i], tank_b_mortality[i]), textcoords="offset points", xytext=(0, 7), ha='center', fontsize=9, fontweight='bold', color='#d62728')

plt.tight_layout()
chart_path = r"c:\Users\Dave\CrayCare\weekly_mortality_chart.png"
plt.savefig(chart_path, dpi=300)
print(f"Chart successfully saved to {chart_path}")
