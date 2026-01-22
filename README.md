# FTC Strategy and Management App
Open Source
Made by FTC Team The Energizers 23417

This application provides a unified platform to organize your whole team. It combines data driven scouting, strategic planning tools, and internal team management into a single mobile and web compatible interface. Please note that this is the first version of the software and we are actively working on more features. Suggestions are always welcome.

## Core Modules

### Scouting and Match Analysis
The app integrates directly with the FTCScout REST API. Users can search for any team worldwide to view their historical performance across different seasons. The analysis engine breaks down scores into autonomous, teleop, and endgame phases. This allows teams to identify specific strengths and weaknesses of potential alliance partners or opponents.

### Predictive Match Simulation
Two simulation models are available:
* Standard Simulation: Uses simple averages from played matches to estimate alliance totals.
* Weighted Prediction (V2): Utilizes a recency weighted algorithm that favors a team's most recent matches. By applying an exponential decay to older data, the app provides a more accurate representation of a team's current form or recent robot improvements.

### Point Estimation and Performance Tiers
This module evaluates a team's historical data to assign a performance tier ranging from Rookie to Elite. It calculates the average points needed to reach the next level. This provides teams with a clear roadmap for improvement based on global competition standards.

### Alliance Selection Strategy
Designed for use during the elimination rounds, this tool ranks available teams based on customizable weighting factors. Teams can prioritize specific match phases such as high autonomous scoring or consistent endgame performance to generate a data backed selection list for building an optimal alliance.

### Autonomous Path Visualizer and Route Planner
This module features an interactive 2D field. Teams can design autonomous routes by dragging a virtual robot across the field tiles. The tool calculates coordinates and headings for each segment. These paths can be saved to Firestore or exported as Java formatted pose code. This code can be directly implemented into a robot's OpMode. A playback feature allows teams to simulate the robot's movement over time.

### Team Operations Management
* Scrum Board: A Kanban style board for tracking technical and non technical tasks. It supports multiple assignees, priority levels, and deadlines.
* Hour Registration: A digital time clock for team members. It allows users to clock in and out of sessions. This provides data for outreach and volunteer hour tracking.
* Pre Match Checklists: A dedicated section for robot inspection and maintenance. Lists can be created for specific events or general maintenance with the ability to assign tasks to individual members.
* Engineering Portfolio Log: A specialized interface for documenting daily activities. Entries are categorized by role and member. This creates a searchable history that simplifies the process of writing the Engineering Portfolio.

### Hardware Utilities and Practice
* Battery Management: A tracking system for the team's battery inventory. Users enter voltage readings after matches or tests. The app then calculates an optimized charging plan. It groups batteries into batches based on the number of available chargers and prioritizes those with the lowest charge or highest assigned priority.
* Drive Practice Mini Game: A top down 2D simulator that supports keyboard and gamepad input. It allows drivers to practice robot movement and turret aiming in a simulated match environment.
* Resource Hub: An integrated PDF viewer for competition manuals and game rules. It features keyword search and quick page navigation.

## Technical Setup

### Prerequisites
* Flutter SDK stable channel installed on your system
* Dart SDK included with the Flutter installation
* Node JS installed to manage the Firebase CLI tools
* A valid Firebase account to host your team database
* Git installed for version control management

### Installation
1. Clone the repository from GitHub to your local development environment using the git clone command.
2. Navigate to the project root directory in your terminal.
3. Run the flutter doctor command to verify that your environment is correctly set up and all necessary toolchains for Android or iOS are available.
4. Execute the flutter pub get command to download and install all required project dependencies. This includes essential libraries for Firebase integration, state management, and the PDF rendering engine.
5. Ensure that your targeted development device or emulator is connected and recognized by Flutter.
6. Follow the Firebase Setup and Integration instructions provided below to link the application to your own cloud infrastructure. This is a critical step for data persistence and authentication.
7. Start the application by running the flutter run command. You can also build a standalone executable for specific platforms using the flutter build command.

### Firebase Setup and Integration
This application requires a Firebase backend to handle user authentication and data persistence. The internal scripts are designed to automatically initialize the required environment and database structures once the initial connection is established. Follow these detailed steps to set up your environment:

#### 1. Project Initialization
* Go to the Firebase Console and create a new project.
* In the Build menu, navigate to Authentication and enable the Email / Password sign in provider.
* Navigate to Cloud Firestore and click Create database. Start in Test mode to allow the initial automated setup to create the required collections.

#### 2. Local Configuration
You must link your local repository to your Firebase project. This requires the Firebase tools and the FlutterFire CLI.
* Install the Firebase tools using npm.
* Login to your account using the firebase login command.
* Activate the FlutterFire CLI by running the dart pub global activate flutterfire_cli command.
* In the root of the project, run the configuration tool using the flutterfire configure command.
* Select your Firebase project from the list and choose the platforms you want to support. This will automatically generate lib/firebase_options.dart and the platform specific configuration files.

#### 3. Automated Database Setup
The internal scripts are designed to automatically initialize the required database structures. After the first login and completion of the Setup page within the app, the system will automatically create and manage the necessary Firestore collections such as users, scrumBoards, and tasks. No manual database schema creation is required in the Firebase Console.

### Customization
The application theme is fully customizable. Users can configure primary colors, header styles, and text themes through the Setup page. These preferences are stored in Firestore and applied globally to the application for all team members.

## Credits and Data Access

### Powered by FTCScout
Match data and scouting analytics are powered by the FTCScout REST API. We express our sincere gratitude to the FTCScout team for providing this invaluable data infrastructure to the FIRST Tech Challenge community. 

The application communicates with api.ftcscout.org. Ensure your network configuration does not block outbound HTTPS traffic to this domain. No individual API key is required for these requests as they use public endpoints.

## Contributing
Contributions that improve the analytical models or the user interface are welcome. Please ensure that any new features maintain consistency with the existing architecture and the team centric data model.

## License
This project is licensed under the MIT License.

## Contact
Xant Veugen
Lead Contributor and creator of the app

FTC Team The Energizers 23417
Email: info.energizers23417@gmail.com
