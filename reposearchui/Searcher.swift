import Foundation

struct RepositorySearchResult: Codable {
	enum CodingKeys: String, CodingKey {
		case totalCount = "total_count"
		case incompleteResults = "incomplete_results"
		case repositories = "items"
	}

	let totalCount: Int
	let incompleteResults: Bool
	let repositories: [Repository]
}

public struct Repository: Codable, Identifiable, Equatable {
	public static func == (lhs: Repository, rhs: Repository) -> Bool {
		return lhs.id == rhs.id
	}

	enum CodingKeys: String, CodingKey {
		case id, name
		case fullName = "full_name"
		case htmlUrl = "html_url"
		case description = "description"
		case owner
	}

	public let id: Int
	let name: String
	let fullName: String
	let htmlUrl: String
	let description: String?
	let owner: Owner
}

struct Owner: Codable {
	enum CodingKeys: String, CodingKey {
		case login
	}

	let login: String
}
/*
 "total_count": 40,
 "incomplete_results": false,
 "items": [
 {
 "id": 3081286,
 "node_id": "MDEwOlJlcG9zaXRvcnkzMDgxMjg2",
 "name": "Tetris",
 "full_name": "dtrupenn/Tetris",
 "html_url": "https://github.com/dtrupenn/Tetris",
 "description": "A C implementation of Tetris using Pennsim through LC4",
 */

public final class Searcher {
	private var myTask: URLSessionDataTask?

	deinit {
		if let task = self.myTask {
//			print("Cancelling existing task...")
			task.cancel()
		}
	}
}

extension Searcher {
	func get(url: URL, done: @escaping (String?, String?)->(Void)) {
		//print("get using url: \(url)")
		let urlrequest = URLRequest.init(url: url)
		let task = URLSession.shared.dataTask(with: urlrequest) { (data, urlresponse, error) in
			if let error = error {
				switch error._code {
				case NSURLErrorCancelled:
					// Cancelled...
					break
				default:
					print("Unexpected error: \(error)")
					break
				}
				return
			}

			var result: String? = nil
			var next: String? = nil

			if let data = data {
				//print("data: \(data)")
				result = String.init(data: data, encoding: .utf8)
			}
			else {
				print("No data, but also no error?")
			}

			if let httpUrlResponse = urlresponse as? HTTPURLResponse {
//				print("\(httpUrlResponse.allHeaderFields)")
				// https://docs.github.com/en/rest/overview/resources-in-the-rest-api#pagination
				if let link = httpUrlResponse.value(forHTTPHeaderField: "link") {
//					print("link: \(link)")
					//
					/*
					 <https://api.github.com/search/repositories?q=banana&page=2>; rel="next", <https://api.github.com/search/repositories?q=banana&page=34>; rel="last"

					 <https://api.github.com/search/repositories?q=banana&page=1>; rel=\"prev\", <https://api.github.com/search/repositories?q=banana&page=3>; rel=\"next\", <https://api.github.com/search/repositories?q=banana&page=34>; rel=\"last\", <https://api.github.com/search/repositories?q=banana&page=1>; rel=\"first\"

<https://api.github.com/search/repositories?q=banana&page=1>; rel=\"prev\",
<https://api.github.com/search/repositories?q=banana&page=3>; rel=\"next\",
<https://api.github.com/search/repositories?q=banana&page=34>; rel=\"last\",
<https://api.github.com/search/repositories?q=banana&page=1>; rel=\"first\"
					 */

					let links = link.components(separatedBy: ",")

					var dictionary: [String: String] = [:]
					links.forEach({
						let components = $0.components(separatedBy:"; ")
						let cleanPath = components[0].trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
//						print("Trimming \(components[0]) into \(cleanPath)")
						dictionary[components[1]] = cleanPath
					})

					if let nextPagePath = dictionary["rel=\"next\""] {
//						print("nextPagePath: \(nextPagePath)")
						next = nextPagePath
					}
					// If ever needed...
//					if let lastPagePath = dictionary["rel=\"last\""] {
//						print("lastPagePath: \(lastPagePath)")
//					}
//					if let firstPagePath = dictionary["rel=\"first\""] {
//						print("firstPagePath: \(firstPagePath)")
//					}
				}
			}

			done(result, next)
		}

		task.resume()
		self.myTask = task
	}
}

public extension Searcher {
	func searchGithubRepositories(_ word: String, done: @escaping ([Repository], String?) -> Void) {
//		print("searchGithubRepositories: \(word)")
		var components = URLComponents()
		components.scheme = "https"
		components.host = "api.github.com"
		components.path = "/search/repositories"
		components.queryItems = [
			URLQueryItem(name: "q", value: word),
		]

		guard let url = components.url else {
			print("Bad url")
			return
		}

		return self.searchRepositoriesByUrl(url: url, done: done)
	}

	func searchRepositoriesByUrl(url: URL, done: @escaping ([Repository], String?) -> Void) {
//		print("searchRepositoriesByUrl: \(url)")
		self.get(url: url) { results, next in
			var repositories = [Repository]()

			defer {
				done(repositories, next)
			}

			guard let results = results else {
				print("Empty search results")
				return
			}

			guard let dataJson = results.data(using: .utf8) else {
				print("Failed getting data")
				return
			}

			do {
				let decoder = JSONDecoder()
				let searchResults = try decoder.decode(RepositorySearchResult.self, from: dataJson)
//				print("searchResults.totalCount: \(searchResults.totalCount)")
				if !searchResults.incompleteResults {
					repositories = searchResults.repositories
				}
			} catch {
				print("decode error: \(error)")
			}
		}
	}
}
