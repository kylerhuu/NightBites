//
//  ContentView.swift
//  NightBites
//
//  Created by Kyler Hu on 2/24/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
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
}
