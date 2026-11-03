import SwiftUI

struct AcknowledgementsView: View {
    var body: some View {
        Form {
            Section("License") {
                LabeledContent {
                    Text("Mozilla Public License 2.0")
                } label: {
                    Text(verbatim: "maekster")
                }
            }

            Section {
                creditButton(project: "Minidisc", author: "NO HIT Dev", url: MaeksterURLs.minidisc)
                creditButton(project: "Cassette", author: "Mathieu Dubart", url: MaeksterURLs.cassette)
            } header: {
                Text("Based On")
            } footer: {
                Text("maekster is a fork of Minidisc by NO HIT Dev, which is itself a fork of Cassette by Mathieu Dubart.")
            }

            Section("Open Source") {
                Button {
                    ExternalLinkOpener.open(MaeksterURLs.swiftSonic)
                } label: {
                    LabeledContent("SwiftSonic") {
                        Text("MIT License")
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                Button {
                    ExternalLinkOpener.open(MaeksterURLs.navidrome)
                } label: {
                    Text("Navidrome")
                }
                .foregroundStyle(.primary)
                Button {
                    ExternalLinkOpener.open(MaeksterURLs.openSubsonic)
                } label: {
                    Text("OpenSubsonic")
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Thanks")
            } footer: {
                Text("Thanks to the Navidrome team for an excellent self-hosted music server, and to the OpenSubsonic community for modernizing the Subsonic API.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A project credit that opens its repository. Project and author names are proper nouns and aren't localized.
    private func creditButton(project: String, author: String, url: URL) -> some View {
        Button {
            ExternalLinkOpener.open(url)
        } label: {
            LabeledContent {
                Text(verbatim: author)
            } label: {
                Text(verbatim: project)
            }
        }
        .foregroundStyle(.primary)
    }
}
