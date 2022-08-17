//
//  ContentView.swift
//  reposearchui
//
//  Created by Jonny Bergström on 2022/08/10.
//

import SwiftUI

struct GithubRepoSearchingApp: View {
	// Internal enums, classes, structs...
	enum Searchstatus: String {
		case idle = "idle"
		case searching = "searching"
	}

	class Searchhelper {
		enum Searchtype {
			case initialSearch(String)
			case continuedSearch
		}

		private var timerDebounce: Timer?
		private var mySearcher: Searcher?
		private var nextPage: URL?
		private let minimumCharactersForSearch = 2

		func search(searchtype: Searchtype, done: @escaping (_ repositories: [Repository])->(Void)) {
			// Remove any existing search.
			if let t = self.timerDebounce {
				t.invalidate()
			}
			self.mySearcher = nil

			func handleResponse(repositoriesIn: [Repository], nextIn: String?) {
				var tempNextPage: URL? = nil
				if let nextIn = nextIn {
					tempNextPage = URL.init(string: nextIn)
				}
				self.nextPage = tempNextPage

				DispatchQueue.main.async {
					done(repositoriesIn)
				}
			}

			// Do checks also here before the throttle, such that we can quit early if needed.
			var failEarly = false
			switch searchtype {
			case .initialSearch(let word):
				if word.count < self.minimumCharactersForSearch {
					failEarly = true
				}
				break

			case .continuedSearch:
				if self.nextPage == nil {
					failEarly = true
				}
				break
			}
			if failEarly {
				handleResponse(repositoriesIn: [], nextIn: nil)
				return
			}

			// Throttle requests, max 1 per second.
			self.timerDebounce = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
				guard let wself = self else {
					return
				}

				let searcherNew = Searcher.init()
				wself.mySearcher = searcherNew

				switch searchtype {
				case .initialSearch(let word):
					wself.nextPage = nil
					if word.count < wself.minimumCharactersForSearch {
						handleResponse(repositoriesIn: [], nextIn: nil)
					}
					else {
						searcherNew.searchGithubRepositories(word, done: handleResponse)
					}
					break

				case .continuedSearch:
					if let next = wself.nextPage {
						wself.nextPage = nil
						searcherNew.searchRepositoriesByUrl(url: next, done: handleResponse)
					} else {
						handleResponse(repositoriesIn: [], nextIn: nil)
					}
					break
				}
			}
		}
	}

	struct CustomTextFieldStyle: TextFieldStyle {
		public func _body(configuration: TextField<Self._Label>) -> some View {
			configuration
				.font(.largeTitle)
				.padding(10)
				.background(
					RoundedRectangle(cornerRadius: 5)
						.strokeBorder(Color.primary.opacity(0.5), lineWidth: 3)
				)
		}
	}

	struct RepoRowView: View {
		struct Avatar: View {
			var url: URL?
			var body: some View {
				if self.url != nil {
					AsyncImage(url: self.url) { asyncImagePhase in
						if let image = asyncImagePhase.image {
							image.resizable().aspectRatio(contentMode: .fit) // Displays the loaded image.
						} else if asyncImagePhase.error != nil {
							Color.red // Indicates an error.
						} else {
							Color.clear // Acts as a placeholder.
						}
					}
				}
			}
		}
		struct LinkIcon: View {
			var url: URL?
			var body: some View {
				if self.url != nil {
					Image(systemName: "globe")
				}
			}
		}

		var repo: Repository
		@State var showSafari = false
		var body: some View {
			VStack(alignment: .trailing, spacing: 0) {
				Button(action: {
					self.showSafari = true
				}) {
					HStack(alignment: .top, spacing: 5) {
						VStack(alignment: .leading) {
							Text(self.repo.fullName)
								.foregroundColor(.primary)
								.font(.headline)
							Text(self.repo.owner.login)
								.foregroundColor(.secondary)
								.font(.footnote)
						}

						Spacer() // Makes the text appear to the left edge of the cell, while the icon appears to the right edge.

						LinkIcon(url: URL.init(string: self.repo.htmlUrl))
							.frame(maxHeight: .infinity) // Makes the icon vertically centered in the cell.
					}
					// This stretches the vstack to "full width"
					.frame(
						maxWidth: .infinity,
						maxHeight: .infinity,
						alignment: .topLeading
					)
				}.sheet(isPresented: $showSafari) {
					if let theurl = URL.init(string: self.repo.htmlUrl) {
						SafariView(url: theurl)
					}
				}
			}
		}
	}

	// Functions
	private func assignRepos(_ reposIn: [Repository]) {
		self.repos = reposIn
	}

	private func appendRepos(_ moreRepos: [Repository]) {
		self.repos.append(contentsOf: moreRepos)
	}

	private func clearRepos() {
		self.repos.removeAll()
	}

	// Properties
	@State var searchtext: String = ""
	@State var searchstatus: Searchstatus = .idle
	@State var repos = [Repository]()
	var searchhelper = Searchhelper.init()
	var body: some View {
		VStack(
			alignment: .leading,
			spacing: 5
		) {
			HStack(alignment: .center, spacing: 3) {
				TextField(
					"Search...",
					text: $searchtext
				)
				.disableAutocorrection(true)
				.submitLabel(.done)
				.textInputAutocapitalization(.never)
				.onChange(of: searchtext) {word in
					self.clearRepos()
					self.searchstatus = .searching
					self.searchhelper.search(searchtype: .initialSearch(word)) { incomingRepos in
						self.searchstatus = .idle
						self.assignRepos(incomingRepos)
					}
				}
				.foregroundColor(.black)
				.multilineTextAlignment(.leading)
				.padding(5)
				.textFieldStyle(CustomTextFieldStyle())

				ProgressView().progressViewStyle(.circular).isHidden(self.searchstatus == .idle)
			}.padding(.trailing, 10)

			List() {
				ForEach(self.repos, id: \.id) { repo in
					RepoRowView(repo: repo).onAppear {
						if repo != self.repos.last {
							return
						}
						// Last element became visible in the list, ask the searcher to fetch more...
						self.searchstatus = .searching
						self.searchhelper.search(searchtype: .continuedSearch) { repositories in
							self.searchstatus = .idle
							self.appendRepos(repositories)
						}
					}
				}
			}
			.listStyle(.grouped)
		}
		.background(Color.init(red: 1, green: 0.8, blue: 0))
		.preferredColorScheme(.light)
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		Group {
			GithubRepoSearchingApp(repos: [
				Repository.init(id: 1, name: "Google", fullName: "Google", htmlUrl: "https://www.google.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 2, name: "Bing", fullName: "Bing", htmlUrl: "https://www.bing.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 3, name: "Bad site", fullName: "Bad site", htmlUrl: "", description: nil, owner: Owner.init(login: "Bad site man")),
			])
			.previewInterfaceOrientation(.portrait)

			GithubRepoSearchingApp(repos: [
				Repository.init(id: 1, name: "Google", fullName: "Google", htmlUrl: "https://www.google.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 2, name: "Bing", fullName: "Bing", htmlUrl: "https://www.bing.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 3, name: "Bad site", fullName: "Bad site", htmlUrl: "", description: nil, owner: Owner.init(login: "Bad site man")),
			])
			.previewInterfaceOrientation(.landscapeLeft)

			GithubRepoSearchingApp(repos: [
				Repository.init(id: 1, name: "Google", fullName: "Google", htmlUrl: "https://www.google.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 2, name: "Bing", fullName: "Bing", htmlUrl: "https://www.bing.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 3, name: "Bad site", fullName: "Bad site", htmlUrl: "", description: nil, owner: Owner.init(login: "Bad site man")),
			])
			.previewDevice("iPad mini (6th generation)")
			.previewInterfaceOrientation(.portrait)
			GithubRepoSearchingApp(repos: [
				Repository.init(id: 1, name: "Google", fullName: "Google", htmlUrl: "https://www.google.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 2, name: "Bing", fullName: "Bing", htmlUrl: "https://www.bing.com", description: nil, owner: Owner.init(login: "Hackerman")),
				Repository.init(id: 3, name: "Bad site", fullName: "Bad site", htmlUrl: "", description: nil, owner: Owner.init(login: "Bad site man")),
			])
			.previewDevice("iPad mini (6th generation)")
			.previewInterfaceOrientation(.landscapeLeft)
		}
	}
}

extension View {
	@ViewBuilder func isHidden(_ isHidden: Bool) -> some View {
		if isHidden {
			self.hidden()
		} else {
			self
		}
	}
}
