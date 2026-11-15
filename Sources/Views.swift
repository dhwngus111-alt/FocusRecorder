import SwiftUI

private enum FocusTheme {
    static let ink = Color(red: 0.19, green: 0.18, blue: 0.23)
    static let muted = Color(red: 0.45, green: 0.43, blue: 0.48)
    static let paper = Color(red: 0.995, green: 0.991, blue: 0.982)
    static let lavender = Color(red: 0.80, green: 0.75, blue: 0.96)
    static let orange = Color(red: 1.00, green: 0.84, blue: 0.71)
    static let green = Color(red: 0.80, green: 0.91, blue: 0.73)
    static let line = Color(red: 0.86, green: 0.84, blue: 0.86)
}

private struct TopologyMark: View {
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            Circle().stroke(FocusTheme.lavender, lineWidth: 2)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: -size * 0.18, y: -size * 0.12)
            Circle().stroke(FocusTheme.orange, lineWidth: 2)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: size * 0.18, y: -size * 0.12)
            Circle().stroke(FocusTheme.green, lineWidth: 2)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.18)
            Circle().fill(FocusTheme.ink).frame(width: 3, height: 3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SoftCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.55), lineWidth: 1))
    }
}

struct TimerPopoverView: View {
    @ObservedObject var store: FocusStore
    let openHistory: () -> Void
    let onStart: () -> Void
    @State private var minutes = "25"
    @FocusState private var minutesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TopologyMark(size: 24)
                Text("집중 타이머").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: openHistory) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("집중 기록과 설정")
            }

            VStack(spacing: 5) {
                Text(TimeText.clock(store.elapsed))
                    .font(.system(size: 46, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(FocusTheme.ink)
                Text(store.active.map { "목표 \(TimeText.duration($0.targetSeconds))" } ?? "집중할 시간을 정하세요")
                    .font(.caption)
                    .foregroundStyle(FocusTheme.muted)
            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityLabel("경과 시간 \(TimeText.duration(store.elapsed))")

            if store.active != nil {
                HStack(spacing: 8) {
                    Button(store.isRunning ? "일시정지" : "계속하기") { store.pauseOrResume() }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("집중 종료") { store.stop() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("집중 시간", text: $minutes)
                        .focused($minutesFocused)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(start)
                    Text("분")
                        .foregroundStyle(.secondary)
                    Button("시작") { start() }
                        .disabled(parsedMinutes == nil)
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
            }

            Rectangle().fill(FocusTheme.line).frame(height: 1).padding(.vertical, 16)

            HStack(spacing: 14) {
                Toggle("화면 표시", isOn: $store.overlayVisible)
                Toggle("항상 위", isOn: $store.alwaysOnTop)
            }
            .toggleStyle(.checkbox)
            .font(.caption)

            HStack(spacing: 10) {
                Text("크기")
                    .frame(width: 28, alignment: .leading)
                Slider(value: $store.overlayFontSize, in: 12...80, step: 1)
                Text("\(Int(store.overlayFontSize))")
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }
            .font(.caption)
            .padding(.top, 11)
            .disabled(!store.overlayVisible)

            Button(action: openHistory) {
                HStack(spacing: 6) {
                    Text("기록과 설정")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(FocusTheme.muted)
            .padding(.top, 17)
        }
        .padding(16)
        .frame(width: 280)
        .foregroundStyle(FocusTheme.ink)
        .tint(FocusTheme.ink)
        .background(FocusTheme.paper)
        .preferredColorScheme(.light)
        .onAppear { if store.active == nil { minutesFocused = true } }
    }

    private var parsedMinutes: Int? {
        guard let value = Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(value) else { return nil }
        return value
    }

    private func start() {
        guard let value = parsedMinutes else { return }
        store.start(minutes: value)
        onStart()
    }
}

struct HistoryView: View {
    @ObservedObject var store: FocusStore
    @State private var selectedDate = Date()
    @State private var shownMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var showDisplaySettings = false

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    private var calendar: Calendar { .current }
    private var selectedRecords: [FocusRecord] {
        FocusStatistics.records(on: selectedDate, from: store.records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    TopologyMark(size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("집중 기록").font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("하루하루 쌓이는 집중 시간")
                            .font(.caption).foregroundStyle(FocusTheme.muted)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    statCard("오늘 평균", value: FocusStatistics.average(on: Date(), from: store.records), tint: FocusTheme.lavender)
                    statCard("이번 주 평균", value: FocusStatistics.weekAverage(containing: Date(), from: store.records), tint: FocusTheme.orange)
                }
                Text("평균은 완료·중단한 모든 세션의 실제 집중 시간을 기준으로 계산합니다.")
                    .font(.caption)
                    .foregroundStyle(FocusTheme.muted)

                VStack(spacing: 12) {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                        Text(shownMonth.formatted(.dateTime.year().month(.wide)))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                        ForEach(weekdays, id: \.self) { day in
                            Text(day).font(.caption).foregroundStyle(FocusTheme.muted)
                        }
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                            if let date {
                                let count = FocusStatistics.records(on: date, from: store.records).count
                                Button {
                                    selectedDate = date
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(calendar.component(.day, from: date))")
                                        Circle()
                                            .fill(count > 0 ? FocusTheme.ink : .clear)
                                            .frame(width: 5, height: 5)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(calendar.isDate(date, inSameDayAs: selectedDate)
                                                ? FocusTheme.green.opacity(0.8) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), 기록 \(count)개")
                            } else {
                                Color.clear.frame(height: 42)
                            }
                        }
                    }
                }
                .padding(14)
                .background(FocusTheme.green.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(FocusTheme.green.opacity(0.55), lineWidth: 1))

                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(.headline)
                    if selectedRecords.isEmpty {
                        Text("이날의 집중 기록이 없습니다.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(selectedRecords) { record in
                            VStack(spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.subheadline.weight(.semibold))
                                        Text("설정 \(TimeText.duration(record.targetSeconds)) · 실제 \(TimeText.duration(record.actualSeconds))")
                                            .font(.caption)
                                            .foregroundStyle(FocusTheme.muted)
                                    }
                                    Spacer()
                                    Text(record.succeeded ? "성공" : "실패")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FocusTheme.ink)
                                }
                            }
                            .padding(12)
                            .background(FocusTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(record.succeeded ? FocusTheme.green : FocusTheme.orange, lineWidth: 1))
                        }
                    }
                }

                DisclosureGroup("화면 설정", isExpanded: $showDisplaySettings) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("화면에 타이머 표시", isOn: $store.overlayVisible)
                        Toggle("항상 다른 창 위에 표시", isOn: $store.alwaysOnTop)
                        HStack {
                            Text("타이머 크기")
                            Slider(value: $store.overlayFontSize, in: 12...80, step: 1)
                            Text("\(Int(store.overlayFontSize)) pt")
                                .frame(width: 42, alignment: .trailing)
                        }
                        Text("화면의 숫자를 드래그하면 위치가 저장됩니다.")
                            .font(.caption)
                            .foregroundStyle(FocusTheme.muted)
                    }
                    .padding(.top, 10)
                }
                .font(.subheadline)
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 620)
        .foregroundStyle(FocusTheme.ink)
        .tint(FocusTheme.ink)
        .background(FocusTheme.paper)
        .preferredColorScheme(.light)
    }

    private func statCard(_ label: String, value: Int?, tint: Color) -> some View {
        SoftCard(tint: tint) {
            HStack(spacing: 10) {
                Circle().stroke(FocusTheme.ink.opacity(0.35), lineWidth: 1)
                    .frame(width: 21, height: 21)
                    .overlay(Circle().fill(tint).frame(width: 7, height: 7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(FocusTheme.muted)
                    Text(value.map(TimeText.duration) ?? "—")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: shownMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: shownMonth)) else { return [] }
        let offset = (calendar.component(.weekday, from: first) - 1 + 7) % 7
        return Array(repeating: nil, count: offset) + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: first)
        }.map(Optional.some)
    }

    private func moveMonth(_ amount: Int) {
        if let date = calendar.date(byAdding: .month, value: amount, to: shownMonth) {
            shownMonth = date
        }
    }
}

