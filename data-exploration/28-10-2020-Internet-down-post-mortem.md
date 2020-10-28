# Internet connection failure

| Reported by    | arthursens   |
|---|---|
| Date | 28-10-2020   |
| Start |  Around 11:50 |
| End | Around 11:56 |
| Root cause found | No |

---

## Incident

Couldn't connect to several websites: Github, Gmail, WaniKani, Slack

## Data exploration executed

Opened grafana's `My notebook` dashboard and looked for the `Network Traffic Basic` panel, and I've seen no anomalies with networking traffic.

![image](https://user-images.githubusercontent.com/24193764/97456475-ad74fe80-1917-11eb-91f0-182a32879ed8.png)

Nothing could be done from there.

Some minutes after that the internet connection came back to normal

## Conclusion

Extra metrics needed. 

## Action Items

Add blackbox exporter to the set up. Pinging most used websites: Gmail, Github, WaniKani, Twitter and Slack.