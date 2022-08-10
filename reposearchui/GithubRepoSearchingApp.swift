//
//  ContentView.swift
//  reposearchui
//
//  Created by Jonny Bergström on 2022/08/10.
//

import SwiftUI

struct GithubRepoSearchingApp: View {
	@State var repos = [Repository]()

	class Searchhelper {
		enum Searchtype {
			case initialSearch(String)
			case continuedSearch
		}
		enum Searchstatus {
			case idle
			case searching
		}

		var searchstatus: Searchstatus = .idle
		private var timerDebounce: Timer?
		private var mySearcher: Searcher?
		private var nextPage: URL?

		func search(searchtype: Searchtype, done: @escaping (_ repositories: [Repository])->(Void)) {
			// Remove any existing search.
			if let t = self.timerDebounce {
				t.invalidate()
			}
			self.mySearcher = nil

			// Throttle requests, max 1 per second.
			self.searchstatus = .searching
			self.timerDebounce = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
				guard let wself = self else {
					return
				}

				let searcherNew = Searcher.init()
				wself.mySearcher = searcherNew

				func handleResponse(repositoriesIn: [Repository], nextIn: String?) {
					var tempNextPage: URL? = nil
					if let nextIn = nextIn {
						tempNextPage = URL.init(string: nextIn)
					}
					//				else {
					//					print("nextIn was nil!")
					//				}
					wself.nextPage = tempNextPage
					//				print("Set nextpage: \(String(describing: tempNextPage)), nextIn: \(String(describing: nextIn))")
					wself.searchstatus = .idle
					DispatchQueue.main.async {
						done(repositoriesIn)
					}
				}

				switch searchtype {
				case .initialSearch(let word):
					wself.nextPage = nil
					if word.count < 1 {
						print("Too short")
						return
					}

					searcherNew.searchGithubRepositories(word, done: handleResponse)
					break

				case .continuedSearch:
					guard let next = wself.nextPage else {
						print("No next page...")
						return
					}
					wself.nextPage = nil

					searcherNew.searchRepositoriesByUrl(url: next, done: handleResponse)
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

	private func assignRepos(_ reposIn: [Repository]) {
		self.repos = reposIn
	}

	private func appendRepos(_ moreRepos: [Repository]) {
		self.repos.append(contentsOf: moreRepos)
	}

	private func clearRepos() {
		self.repos.removeAll()
	}

	@State var searchtext: String = ""
	@State var searchhelper = Searchhelper.init()
	var body: some View {
		VStack(
			alignment: .leading,
			spacing: 5
		) {
			TextField(
				"Search...",
				text: $searchtext
			)
			.disableAutocorrection(true)
			.submitLabel(.done)
			.textInputAutocapitalization(.never)
			.onChange(of: searchtext) {word in
				self.clearRepos()
				self.searchhelper.search(searchtype: .initialSearch(word)) { incomingRepos in
					self.assignRepos(incomingRepos)
				}
			}
			.foregroundColor(.black)
			.multilineTextAlignment(.leading)
			.padding(5)
			.textFieldStyle(CustomTextFieldStyle())

			List() {
				ForEach(self.repos, id: \.id) { repo in
					RepoRowView(repo: repo).onAppear {
						if repo != self.repos.last {
							return
						}
						// Last element became visible in the list, ask the searcher to fetch more...
						self.searchhelper.search(searchtype: .continuedSearch) { repositories in
							self.appendRepos(repositories)
						}
					}
				}
			}
			.listStyle(.grouped)
		}
		.background(Color.init(red: 1, green: 0.8, blue: 0))
		.preferredColorScheme(.light)
		.overlay {
			if self.searchhelper.searchstatus == .searching {
				ProgressView().progressViewStyle(.circular)
				//.scaleEffect(x: 1.0, y: 1.0, anchor: .center)
			}
		}
	}

	struct DarkBlueShadowProgressViewStyle: ProgressViewStyle {
		func makeBody(configuration: Configuration) -> some View {
			ProgressView(configuration)
				.shadow(color: Color(red: 0, green: 0, blue: 0.6),
						radius: 4.0, x: 1.0, y: 2.0).frame(width: 50, height: 50, alignment: .center)
		}
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
