# CrayCare Data Flow Diagrams

## Data Flow Diagram Level 0

```mermaid
flowchart TB
    ADMIN[System Admin]
    OWNER[Farm Owner]
    ESP[IoT Hardware System]
    SYSTEM((0.0 CrayCare<br/>IoT and Mobile Based Smart<br/>Aquaculture System))

    ADMIN -->|User account status updates| SYSTEM
    ADMIN -->|Hardware assignment updates| SYSTEM
    SYSTEM -->|User list and account status| ADMIN
    SYSTEM -->|Hardware assignment status| ADMIN

    OWNER -->|Monitoring requests| SYSTEM
    OWNER -->|Historical sensor data requests| SYSTEM
    OWNER -->|Grow-out records| SYSTEM
    OWNER -->|Sensor threshold settings| SYSTEM
    OWNER -->|Feeding schedules and commands| SYSTEM
    OWNER -->|Actuator mode requests| SYSTEM
    SYSTEM -->|Dashboard data| OWNER
    SYSTEM -->|Historical sensor data| OWNER
    SYSTEM -->|Alerts and notifications| OWNER
    SYSTEM -->|Anomaly detection results| OWNER
    SYSTEM -->|Growth trends| OWNER
    SYSTEM -->|Reports| OWNER
    SYSTEM -->|Feeding status| OWNER
    SYSTEM -->|Actuator status| OWNER

    ESP -->|Water-quality sensor readings| SYSTEM
    ESP -->|Water-level reading| SYSTEM
    ESP -->|Feed-level reading| SYSTEM
    ESP -->|Feeder status| SYSTEM
    ESP -->|Actuator status| SYSTEM
    SYSTEM -->|Sensor thresholds| ESP
    SYSTEM -->|Feeding schedules and commands| ESP
    SYSTEM -->|Actuator modes| ESP
```

## Data Flow Diagram Level 1

```mermaid
flowchart TB
    ADMIN[System Admin]
    OWNER[Farm Owner]
    ESP[IoT Hardware System]

    P1((1.0 Real Time<br/>Monitoring))
    P2((2.0 Tank Grow out<br/>Record Management))
    P3((3.0 Feeding and<br/>Actuator Control))
    P4((4.0 Notification<br/>and Alerting))
    P5((5.0 Historical Analytics<br/>Anomaly Detection<br/>and Reporting))
    P6((6.0 Settings and<br/>Profile Management))
    P7((7.0 User Account Status<br/>and Hardware Assignment<br/>Management))

    D1[(D1 Grow out Records)]
    D2[(D2 Sensor Data)]
    D3[(D3 Feeding and Actuator Data)]
    D4[(D4 Notifications)]
    D5[(D5 User Profiles and Preferences)]
    D6[(D6 Hardware Assignment Data)]
    D7[(D7 Water Quality Anomaly Detection Data)]
    D8[(D8 Sensor Thresholds)]

    OWNER -->|Monitoring request| P1
    P1 -->|Current dashboard data and device status| OWNER
    ESP -->|Temperature, pH, dissolved oxygen, turbidity, water-level, and feed-level readings| P1
    P1 -->|Latest sensor readings| D2
    D2 -->|Current sensor data| P1

    OWNER -->|Sampling, mortality, harvest, and batch records| P2
    P2 -->|Grow out status, growth records, sampling history, mortality history, and harvest history| OWNER
    P2 -->|Saved grow out records| D1
    D1 -->|Existing grow out records| P2

    OWNER -->|Feed now, schedules, and actuator mode requests| P3
    P3 -->|Feeding status, feeder status, and actuator status| OWNER
    P3 -->|Sensor thresholds, feeding schedules, feeding commands, and actuator modes| ESP
    ESP -->|Feeder, aerator, water-pump, and actuator status| P3
    P3 -->|Feeding schedules, feeding activity, and actuator logs| D3
    D3 -->|Feeding and actuator records| P3

    D2 -->|Water condition data| P4
    D3 -->|Operational status changes| P4
    P4 -->|In-app alerts and push notifications| OWNER
    P4 -->|Saved notification records| D4
    D4 -->|Notification history| P4

    D1 -->|Growth, sampling, mortality, and harvest records| P5
    D2 -->|Historical sensor readings| P5
    D7 -->|Stored anomaly detection results| P5
    OWNER -->|Historical data, growth trend, and report requests| P5
    P5 -->|Current and historical anomaly detection results| D7
    P5 -->|Historical sensor data, growth trends, anomaly detection results, and reports| OWNER
    OWNER -->|Settings and profile updates| P6
    P6 -->|Updated profile and settings| OWNER
    P6 -->|Saved profile and preference data| D5
    D5 -->|Profile and preference data| P6
    P6 -->|Saved threshold settings| D8
    D8 -->|Sensor threshold settings| P6
    P6 -->|Updated sensor thresholds| P3

    ADMIN -->|User account status updates| P7
    ADMIN -->|Hardware assignment updates| P7
    P7 -->|User list and account status| ADMIN
    P7 -->|Hardware assignment status| ADMIN
    P7 -->|Updated user account status| D5
    D5 -->|User profiles and account status| P7
    P7 -->|Updated hardware assignment data| D6
    D6 -->|Hardware assignment records| P7
```

## Diagram Notes

- The ML anomaly detector is represented inside Process 5.0 because it is a supporting CrayCare function, not an external actor.
- Feed level is included in the IoT Hardware System data for feeder monitoring, but it is not an input to water quality anomaly detection.
- D1 stores batch, sampling, mortality, and harvest records.
- D2 stores the latest sensor data and historical sensor readings used by monitoring, alerting, and analytics.
- D7 stores the current and hourly historical water-quality anomaly-detection results.
- D8 stores the sensor-threshold settings used by actuator control.
- Reports and growth trends are computed from stored records and returned to the owner; they are not separate stored tables.
