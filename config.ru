require_relative 'app'

# Serve assets before the app's session middleware. Inside it, every SVG/CSS/JS
# response re-sends the session cookie it was requested with; one that was in
# flight while a request changed the session (joining a room, making a move)
# lands last and silently reverts the session, e.g. dropping your 1v1 seat.
use Rack::Static, urls: ['/css', '/js', '/pieces', '/favicon.svg'], root: File.join(__dir__, 'public')

run App
