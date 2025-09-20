from app import getReccoSongProperties, geminiCall, get_spotify_id, get_album_art

#Spotifyids = ['5CZ40GBx1sQ9agT82CLQCT', '2TOzTqQXNmR2zDJXihjZ2e', '4ZtFanR9U6ndgddUvNcjcG', '5wANPM4fQCJwkGd4rN57mH', '6HU7h9RYOaPRFeh0R3UeAr', '0MMyJUC3WNnFS1lit5pTjk', '6SRsiMl7w1USE4mFqrOhHC', '4wcBRRpIfesgcyUtis7PEg', '5JCoSi02qi3jJeHdZXMmR8', '6P4d1NWBCNIYZjzF9k1mVN', '61W7tEpxEfmizp6V5ZRN10']


Spotifyids = ['4nRhbx8L4ifnMKaE5jSQGR', '0j35X8cTq543QDYLOyqB8W', '5vJaDPHpkVAXetkF8YD88S', '2Wc6WJFIh86EDnlMxIKhv8', '6FRQ4HYndOhM4OlVt0Ou3L', '54X78diSLoUDI3joC2bjMz', '2s1sdSqGcKxpPr5lCl7jAV', '5g9f8tdbqs0yesSoHeFo62', '1GLIlVpCxVSAFyHls6eE0C', '538wQWciNel44Cwe5tqF9n', '1pjATX7sbd6Y4jMVqIvzHk', '4iIskIFGOnOS6pSwggKosI', '1dyHU9CgeTWIvb2serBHzE', '448aYzBX7pdzeNoJVw1QeA', '1YrnDTqvcnUKxAIeXyaEmU', '3ovQbkPW0RGloaaW4Gg4fK', '6gz6rxRge7BLRreM9uJXxI', '57ebBLITHpRgRKGrlbxMZS', '5G2g1EbEtFSMkMbAnhl7FV', '1WadE5KTwPPMruyCPSnVos', '1GqlvSEtMx5xbGptxOTTyk', '6R8524LWtCjlpMMeDP0waL', '423hwXFgoN8RYmqLoLuVvY', '4eHbdreAnSOrDDsFfc4Fpm', '0GD6Ug6ouPqkthlnT058aC', '1v98rfd0an913AzHvMNG8a', '1zgIt6PsAJcbKrDloi3dxt', '5GgFOblnQHXViOJymdtVP0', '37BmiT0Rgv3ui8MPnE02sZ', '1CSaCKPIp2yCIDL3t7Fyau', '0cqcRqZgkNHanWQ8slYA0v', '1MiWGSGDC5mGoP3MNclZ7s', '5d7wn8zwM98iGU9ceTHvWB', '3NrP99Q7bJ8KBgin3rO6Lb', '612VcBshQcy4mpB2utGc3H', '15j9XMtlPVsJpqCrDTv0MW', '79WLCOghf9QMQvSy3B96ep', '6T48yPpivrZlHuw7Tx8M3U', '6qmLe59Zdjj5yQNsQ2iGLT', '51xBgzcyzojRpqFW2ICQAB', '5HvS9Y9Y9ghVggW1o7Erkv', '1M5oDBrdJNXLSo3cBbblcK', '2ZgZZTIR9y4tQfC1mhKb2H', '5y1Uc72BAKxaleTEXpcJJq', '1XqiCbctB4ABx72gOMuSZR', '2K5LRXf7eGH9HzdeNPZc2a', '07L7jNEtQPgTlkwOllZLoA', '1r3qSVN2RdsnyeGVQEjjBH', '2dYwMUAKMLn0e39vIVbuJV', '5j3YamFozZat2AtYy3ifjJ', '6YmCRLGEWhCZbK7zEn6ijl', '6yOKuGcBmboFP5NXpQhZTY', '41vzcBAPXYKoCQqUjv3Bo4', '76O0hU9FsNzhobYTloVpyA', '0xbUb9AjCr9yASgGTqhZWu', '1HlE4vlaQ9cSFBGZHVmuaO', '4mZD5FNfphhARvjgjDNEWt', '4lE3vMcpbYB0ffq61iwiX8', '67ogz3Hz2JF5n2fgjqrH7N', '1zwNC4HIvgQQ6nga0ygjIg', '4EoRaVjUJQze7QjOtp2WCv', '7kIgutuFUva6xCcdzw6tW4', '1erbCGrFMmt7nsafD2TeDJ', '4Fc0Spu8d6jbiE915h9mOC', '1CmOMIQMJoY6jODLS1oTgB', '1cxP7aWWTjqlIPuQvFe2j1', '3YcQnVYnUktq9JUr4zafyS', '47xdo9qYjAbOIVVBAqom1b', '6fiiZlDvqfNOrQC0L7oSX8', '7uIA6z6xmIKMMM3M6cfHRQ', '0O01mOzeMlE64Gvi08dsD6', '2278fNkTiLQb3bjQ5tWAeH', '4OC3anbN4Xgq08LJhC1fgV', '6O1x5c79fKwC1dKLzZ5UPd', '6FR23TfaYKBA4ja2L0VA1B', '1liA8vPMY82TEFSnIBOytR', '7c0XHUkwnVA6MMSdt5z973', '6Wbetf6SSYBl20XEakx7yG', '2xizRhme7pYeITbH1NLLGt', '3mMqk2MAWy2pT1E73nYauu', '37FcNfCFA20AQuYOE3u9kE', '0gukC0ozJO6t1TruWAHsri', '0vm7QUQN5oSsgCpTaktYvm', '3upGBo5doSqZL7QxPutHXo', '7zfCcS97ThY8yhAyaZzrlJ', '6QbqQuah5VjgbdQ7V4bNyr', '1XzRSfoCBFJU4jbZM2AL5P', '3k1hBlWdPrXDSNcuQ56GDt', '23Dw9tOYT6rUeq9cTG6BDs', '06J1f9uoOeOwmkEDUNYfdg', '0GvxgVo7IuXuE1cZZJFt3I', '2DSxY4j6BGIIjHtpjZ3A7D', '0A1Iy8igTvcN0TckqlnR6N', '1l70m0uPhxPJg2eL4eI8I9', '6YMBs9AL3LSGDMJkqfkKjo', '2h3W08zq4Ub276rCG40Wg5', '6vS8JCT9WqTFeAuu8smjRF', '1cmigB9I6IRpFqjIbzvSQB', '6X5TOSckOqubhqy8zbioNR', '02fv3KjMxZCUBkrWWPUsBo']
songprops = getReccoSongProperties(Spotifyids)
print(songprops)
print(len(songprops))
print(len(Spotifyids))



"""
song_id = get_spotify_id("Shape of You", "Ed Sheeran")
print("Spotify ID:", song_id)
print(get_album_art(song_id))
"""