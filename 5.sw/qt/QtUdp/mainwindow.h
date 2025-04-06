#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QUdpSocket>
#include <QThread>
#include <QLabel>
#include "ui_mainwindow.h"
#include "udpcommunicator.h"


class MainWindow : public QMainWindow
{
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = 0);
    ~MainWindow();

private slots:
    void on_pushButton_clicked();

private:
    Ui::MainWindow *ui;
    UDPCommunicator *mUdpCommunicator;
    QSharedPointer<QThread> mUdpCommunicatorThread;

};

#endif // MAINWINDOW_H
