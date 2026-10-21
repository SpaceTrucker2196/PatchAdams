~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
~ synthetic base line 4 ~
~ synthetic base line 5 ~
~ synthetic base line 6 ~
~ synthetic base line 7 ~
~ synthetic base line 8 ~
~ synthetic base line 9 ~
~ synthetic base line 10 ~
~ synthetic base line 11 ~

func main() {
	brews := repo.NewBrewRepository("kettle.db")
	queue := core.NewTaskQueue(4)
	logs := tasklog.NewManager("logs")
	svc := service.NewBrewTaskService(brews, queue, logs)
	srv := api.NewServer(svc)
