import FabBar
import SwiftUI

enum AppTab: Hashable {
    case home
    case explore
    case profile
}

@available(iOS 26.0, *)
struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var showingSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.home) {
                TabContentView(title: "Home", systemImage: "house.fill")
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

            Tab(value: AppTab.explore) {
                TabContentView(title: "Explore", systemImage: "map.fill")
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

            Tab(value: AppTab.profile) {
                TabContentView(title: "Profile", systemImage: "person.fill")
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .fabBar(
            selection: $selectedTab,
            tabs: [
                FabBarTab(value: .home, title: "Home", systemImage: "house.fill", onReselect: {
                    print("Reselected: home")
                }),
                FabBarTab(value: .explore, title: "Explore", systemImage: "map.fill", onReselect: {
                    print("Reselected: explore")
                }),
                FabBarTab(value: .profile, title: "Profile", systemImage: "person.fill", onReselect: {
                    print("Reselected: profile")
                }),
            ],
            action: FabBarAction(
                systemImage: "plus",
                accessibilityLabel: "Add"
            ) {
                showingSheet = true
            }
        )
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showingSheet) {
            Text("Sheet content")
                .presentationDetents([.medium])
        }
    }
}

struct TabContentView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
            .navigationTitle(title)
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView()
    } else {
        Text("Requires iOS 26")
    }
}
