#include "mainwindow.h"

#include <QtWidgets>
#include <QtNetwork>
#include <QThread>

MainWindow::MainWindow(QWidget *parent)
    :QMainWindow(parent), ui(new Ui::MainWindow)
{
    ui->setupUi(this);

    mUdpCommunicator = new UDPCommunicator();
    mUdpCommunicatorThread = QSharedPointer<QThread>(new QThread());
    connect(mUdpCommunicatorThread.data(), &QThread::finished, mUdpCommunicator, &QObject::deleteLater);
    connect(mUdpCommunicatorThread.data(), &QThread::started, mUdpCommunicator, &UDPCommunicator::initialize);
    mUdpCommunicator->moveToThread(mUdpCommunicatorThread.data());
}

MainWindow::~MainWindow()
{
    delete ui;
    if (!mUdpCommunicatorThread.isNull()) {
        mUdpCommunicatorThread->quit();
        mUdpCommunicatorThread->wait();
    }
}

void MainWindow::on_pushButton_clicked()
{
     qInfo() << "Start()";
     mUdpCommunicatorThread->start(QThread::NormalPriority);
}
