.pragma library

function fuzzyScore(text, query) {
  var haystack = String(text || "").toLowerCase()
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return 0

  var direct = haystack.indexOf(needle)
  if (direct !== -1) return 1000 - direct

  var score = 0
  var position = -1
  var previous = -2
  for (var i = 0; i < needle.length; i++) {
    position = haystack.indexOf(needle.charAt(i), position + 1)
    if (position === -1) return -1
    score += position === previous + 1 ? 12 : 3
    score -= Math.min(position, 30) * 0.05
    previous = position
  }
  return score
}

function filterHosts(hosts, query) {
  var source = hosts instanceof Array ? hosts : []
  var terms = String(query || "").trim().toLowerCase().split(/\s+/).filter(function(term) {
    return term !== ""
  })
  if (terms.length === 0) return source

  var matches = []
  for (var i = 0; i < source.length; i++) {
    var host = source[i]
    var text = String(host.searchText || host.alias || "")
    var score = 0
    var matched = true
    for (var j = 0; j < terms.length; j++) {
      var termScore = fuzzyScore(text, terms[j])
      if (termScore < 0) {
        matched = false
        break
      }
      score += termScore
    }
    if (matched) matches.push({ host: host, score: score, index: i })
  }

  matches.sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score
    return a.index - b.index
  })
  return matches.map(function(match) { return match.host })
}
