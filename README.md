# NightBites

NightBites is a native iOS app built to help users discover and order from live food trucks in real time.

Food trucks are mobile by nature, but most ordering platforms are built for static restaurants. NightBites rethinks food discovery around mobility.

---

## The Problem

Food trucks move frequently and operate dynamically.

Customers often:
- Don’t know where trucks are located
- Miss operating hours
- Wait in long lines
- Rely on inconsistent social media updates

Trucks lack:
- A centralized live presence
- Real-time discoverability
- Simple mobile ordering built for mobility

---

## The Solution

NightBites is a mobile-first discovery and ordering platform designed specifically for food trucks.

The app allows:

### For Customers
- Discover nearby live food trucks
- View real-time truck location on a map
- Browse live menus
- Place orders directly through the app
- Track order status

### For Food Trucks
- Toggle live / offline status
- Share real-time GPS location
- Manage menus dynamically
- Mark items sold out instantly
- Receive and manage incoming orders

---

## Core Features

- Native iOS interface built with SwiftUI
- Live location tracking using CoreLocation
- Map integration with MapKit
- User authentication via Firebase
- Real-time database updates using Cloud Firestore
- Order management system (CRUD functionality)
- Status-based availability toggle

---

## Tech Stack

### Mobile App
- Swift
- SwiftUI
- MapKit
- CoreLocation

### Backend Services
- Firebase Authentication
- Cloud Firestore (real-time NoSQL database)
- Firebase Cloud Messaging (for notifications)

### Deployment
- Apple Developer Program
- TestFlight distribution

---

## Architecture Overview

NightBites follows a client-server model:

- The iOS app handles UI, location tracking, and user interaction.
- Firebase manages authentication, real-time data syncing, and order storage.
- Live truck locations and menu updates are reflected instantly via Firestore listeners.

The system is designed to prioritize responsiveness and real-time updates, which are critical for mobile vendors.

---

## Development Status

Early-stage MVP.

Core discovery, live tracking, and ordering logic implemented.
Iterating on UI refinement and performance optimization.

---

## Future Improvements

- Push notification enhancements
- Payment integration (Stripe / Apple Pay)
- Analytics dashboard for trucks
- Multi-city scalability model
- Demand heatmap visualization

---

## Author

Kyler Hu
