//
//  ContentView.swift
//  NightBites
//
//  Created by Kyler Hu on 2/24/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(FoodTruckViewModel.self) private var foodTruckViewModel

    var body: some View {
        Group {
            if !authViewModel.isSignedIn {
                AuthGateView()
            } else if authViewModel.currentUser?.role == .owner {
                OwnerRootView()
            } else {
                StudentRootView()
                    // Student UI is dark-first; without this, system Light Mode keeps dark text on dark surfaces.
                    .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            if authViewModel.isSignedIn {
                foodTruckViewModel.startSupabaseOrdersRealtimeIfNeeded()
            }
        }
        .onChange(of: authViewModel.isSignedIn) { _, isSignedIn in
            if isSignedIn {
                foodTruckViewModel.startSupabaseOrdersRealtimeIfNeeded()
            } else {
                foodTruckViewModel.stopSupabaseOrdersRealtime()
            }
        }
    }
}
