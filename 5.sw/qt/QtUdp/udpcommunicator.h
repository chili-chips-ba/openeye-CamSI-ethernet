#ifndef UDPCOMMUNICATOR_H
#define UDPCOMMUNICATOR_H

#include <QObject>
#include <QScopedPointer>
#include <QtNetwork>
#include <QUdpSocket>
#include <QDebug>

#include "opencv2/core/core.hpp"
#include "opencv2/highgui/highgui.hpp"

class UDPCommunicator : public QObject
{
    Q_OBJECT

public:
    explicit UDPCommunicator(QObject *parent = 0);
    ~UDPCommunicator();


private:
    QUdpSocket *socket = nullptr;
    QHostAddress hostAddress;
    QSharedPointer<QTimer> mDisplayTimer;      
    QByteArray datagram;
    cv::Mat image;
    qint64 currentTime;
    uint8_t frame, frame_prev;

private slots:
    void processPendingDatagrams();

public slots:
    void display();
    void initialize();

};

#endif // UDPCOMMUNICATOR_H
