import SwiftUI

struct ContentView: View {
    @State private var results: [CheckResult] = []
    @State private var isRunning = false

    private var detectedCount: Int { results.filter { $0.detected }.count }
    private var totalCount: Int { results.count }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header card
                        if !results.isEmpty {
                            headerCard
                        }

                        // Results
                        if results.isEmpty {
                            emptyState
                        } else {
                            resultsGrid
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("JB Detector")
            .toolbar {
                Button(action: runChecks) {
                    if isRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .disabled(isRunning)
            }
        }
        .onAppear {
            if results.isEmpty { runChecks() }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detectedCount == 0 ? "CLEAN" : "JAILBREAK DETECTED")
                        .font(.headline)
                        .foregroundColor(detectedCount == 0 ? .green : .red)
                    Text("\(detectedCount)/\(totalCount) checks triggered")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: totalCount > 0 ? CGFloat(detectedCount) / CGFloat(totalCount) : 0)
                        .stroke(detectedCount == 0 ? Color.green : Color.red, lineWidth: 8)
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                    Text("\(detectedCount)")
                        .font(.title2.bold())
                        .foregroundColor(detectedCount == 0 ? .green : .red)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("Tap Play to scan")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(results) { result in
                resultCard(result)
            }
        }
    }

    private func resultCard(_ result: CheckResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.detected ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(result.detected ? .red : .green)
                Spacer()
            }
            Text(result.name)
                .font(.caption.bold())
                .lineLimit(2)
                .foregroundColor(.primary)
            Text(result.details)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private func runChecks() {
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let checks = JBDetector.runAllChecks()
            DispatchQueue.main.async {
                withAnimation {
                    results = checks
                    isRunning = false
                }
            }
        }
    }
}
