+++
title = "Concurrent iterations in Go"
date = "2017-02-27"
author = "Zignd"
cover = ""
tags = ["go", "concurrency"]
keywords = ["go", "concurrency"]
description = ""
showFullContent = false
+++

The Go programming language is very flexible when it comes to concurrency, the language syntax allows you create most of the concurrency flows that might come to your mind. But with this flexibility comes some complexity too. Below you will find some code I wrote when I was experimenting with the tools available in the default packages in order to build a few concurrent flows that came to my mind. The code is below is documented with comments placed where I found worth documenting. The following packages were used throughout the code:

* [Channel types](https://golang.org/ref/spec#Channel_types)
* [sync.WaitGroup](https://golang.org/pkg/sync/#WaitGroup)
* [Select statements](https://golang.org/ref/spec#Select_statements)

## Controlled concurrency

This type of iteration has a controlled number of concurrent tasks being executed.

```go
import (
    "fmt"
    "sync"
    "time"
)

func controlledConcurrency() {
    // Note that the process should have more tasks to execute than the amount
    // it is allowed to execute concurrently. Because there is no point in doing
    // the opposite. tasks > concurrency.
    const tasks = 100

    counter := 0

    // To achieve that a buffered channel is needed, the channel length should
    // be the amount of tasks we want to concurrently execute.
    const concurrency = 30
    tokens := make(chan struct{}, concurrency)
    defer close(tokens)
    for i := 0; i < concurrency; i++ {
        tokens <- struct{}{}
    }

    // A sync.WaitGroup is used to allow the function to wait for the concurrent
    // tasks to finish before it return the control to the caller.
    var wg sync.WaitGroup

    for i := 0; i < tasks; i++ {
        // Increment the sync.WaitGroup before getting into the go routine.
        wg.Add(1)

        go func(i int) {
            // Take a token from the tokens channel, doing so will indicate that
            // one of the concurrent tasks are being executed and will prevent
            // more than the allowed amount of tasks to execute concurrently.
            // It works because as soon as the channel runs out of tokens
            // further receive operations on it will lock until a token is sent
            // back to the channel.
            token := <-tokens
            // Release the token and decrement the sync.WaitGroup counter at the
            // end of the task.
            defer func() { tokens <- token }()
            defer wg.Done()

            // Perform the task.
            time.Sleep(1000 * time.Millisecond)
            counter = counter + 1
            fmt.Println("finished task", i)
        }(i)
    }

    // Wait for the tasks to finish.
    wg.Wait()

    fmt.Printf("finished %d tasks\n", counter)
}
```

## Controlled concurrency stopping on the first error

This type of iteration has a controlled number of concurrent tasks being executed but it also has a mechanism that allows it to stop at the first error.

```go
import (
    "fmt"
    "sync"
    "time"
)

func controlledConcurrencyStoppingOnFirstError() {
    // Note that the process should have more tasks to execute than the amount
    // it is allowed to execute concurrently. Because there is no point in doing
    // the opposite. tasks > concurrency.
    const tasks = 100

    counter := 0

    // To achieve that a buffered channel is needed, the channel length should
    // be the amount of tasks we want to concurrently execute.
    const concurrency = 30
    tokens := make(chan struct{}, concurrency)
    defer close(tokens)
    for i := 0; i < concurrency; i++ {
        tokens <- struct{}{}
    }

    // In this type of loop it is usually expected to be able to have access to
    // error value, to do so every iteration should return a result value, the
    // result in this case have a task field and an err field, and whenever
    // an error occurs during an iteration a result value should be return with
    // an error in the err field.
    results := make(chan *result, tasks)

    // It is also necessary to have a channel that will be used to notify the
    // loop that it should stop.
    abort := make(chan struct{})

    // A sync.WaitGroup is used to allow the function to wait for the concurrent
    // tasks to finish before it return the control to the caller.
    var wg sync.WaitGroup

    for task := 0; task < tasks; task++ {
        // Increment the sync.WaitGroup before getting into the go routine.
        wg.Add(1)

        fmt.Println(task, "...")
        go func(task int) {
            // Decrement the sync.WaitGroup counter at the end of the task.
            defer wg.Done()
            // Use a select statement to abort any pending operation ASAP
            select {
            // Take a token from the tokens channel, doing so will indicate that
            // one of the concurrent tasks are being executed and will prevent
            // more than the allowed amount of tasks to execute concurrently.
            // It works because as soon as the channel runs out of tokens
            // further receive operations on it will lock until a token is sent
            // back to the channel.
            case token := <-tokens:
                defer func() { tokens <- token }()
                results <- doWork(counter, task)
            case <-abort:
                return
            }
        }(task)
    }
    // The closer go routine below is necessary to unlock the for loop that
    // receives from the results channel, not doing so will create a deadlock as
    // soon as the loop above finishes the tasks.
    go func() {
        wg.Wait()
        close(results)
    }()

    // Consumes the results channel and abort the whole operation on the first
    // error.
    for result := range results {
        if result.err != nil {
            fmt.Println(result.task, "Fail")
            fmt.Printf("sending abort sign: %v\n", result.err)
            close(abort)
            break
        } else {
            counter = counter + 1
            fmt.Println(result.task, "Ok")
        }
    }

    fmt.Printf("finished %d tasks\n", counter)
}

type result struct {
    task int
    err  error
}

func doWork(counter int, task int) *result {
    if counter > 30 {
        return &result{
            task: task,
            err: fmt.Errorf("an error occurred at counter: %d, task: %d",
                counter, task)}
    }

    time.Sleep(100 * time.Millisecond)
    return &result{task: task}
}
```