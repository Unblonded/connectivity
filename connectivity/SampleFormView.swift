//
//  SampleFormView.swift
//  connectivity
//
//  Created by Edmund Edjhuryan on 9/9/26.
//
import SwiftUI

struct SampleFormView: View {
    @Binding var samples: [ConnectivitySample]
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var lat = ""
    @State private var lng = ""
    @State private var signal = 3
    @State private var up = ""
    @State private var down = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(samples) { sample in
                HStack {
                    Circle()
                        .fill(sample.signalTier.color)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(sample.name).bold()
                        Text("Signal \(sample.signal)").font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button("Edit") { load(sample) }
                    Button(role: .destructive) {
                        samples.removeAll { $0.id == sample.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            TextField("Name (e.g., 'Hillcrest')", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Latitude", text: $lat).keyboardType(.decimalPad)
                TextField("Longitude", text: $lng).keyboardType(.decimalPad)
            }
            .textFieldStyle(.roundedBorder)

            Picker("Signal", selection: $signal) {
                ForEach(0...5, id: \.self) { Text("\($0)") }
            }
            .pickerStyle(.segmented)

            HStack {
                TextField("MB up (optional)", text: $up).keyboardType(.decimalPad)
                TextField("MB down (optional)", text: $down).keyboardType(.decimalPad)
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button(editingID == nil ? "Add Sample" : "Save Sample") { save() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel") { reset() }
            }
        }
    }

    private func load(_ sample: ConnectivitySample) {
        editingID = sample.id
        name = sample.name
        lat = String(sample.latitude)
        lng = String(sample.longitude)
        signal = sample.signal
        up = sample.mbUp.map { String($0) } ?? ""
        down = sample.mbDown.map { String($0) } ?? ""
    }

    private func save() {
        guard let latVal = Double(lat), let lngVal = Double(lng), !name.isEmpty else { return }
        let sample = ConnectivitySample(
            id: editingID ?? UUID(),
            name: name, latitude: latVal, longitude: lngVal,
            signal: signal, mbUp: Double(up), mbDown: Double(down)
        )
        if let editingID, let idx = samples.firstIndex(where: { $0.id == editingID }) {
            samples[idx] = sample
        } else {
            samples.append(sample)
        }
        reset()
    }

    private func reset() {
        editingID = nil; name = ""; lat = ""; lng = ""; signal = 3; up = ""; down = ""
    }
}
